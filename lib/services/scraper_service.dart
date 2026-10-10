import 'dart:async';
import 'dart:convert';

import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/services/browser_resolver.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

import 'package:xml/xml.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';

class ScraperService {
  static const String _baseUrl = 'https://fitgirl-repacks.site';
  static const String _popularUrl = '$_baseUrl/popular-repacks/';
  static const String _sitemapIndexUrl = '$_baseUrl/sitemap_index.xml';

  // Singleton pattern
  static final ScraperService _instance = ScraperService._internal();

  factory ScraperService() {
    return _instance;
  }

  ScraperService._internal();

  WebClient _web = WebClient();

  @visibleForTesting
  set client(WebClient client) => _web = client;

  // Game pages are fetched by lists and again by the details screen.
  final Map<String, (DateTime, Game)> _detailsCache = {};
  static const _detailsTtl = Duration(minutes: 15);

  /// Streams popular games one by one
  Stream<Game> streamPopularGames() async* {
    try {
      final response = await _web.get(Uri.parse(_popularUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to load popular games');
      }

      final document = parser.parse(response.body);
      final elements = document.querySelectorAll('.bump-view');

      // Limit to first 10 popular games
      final topElements = elements.take(10);

      final links = <String>[];
      for (var element in topElements) {
        final link = element.attributes['href'];
        final lowerTitle = (element.attributes['title'] ?? '').toLowerCase();
        if (link != null &&
            link.contains('fitgirl-repacks.site') &&
            !lowerTitle.contains('upcoming repacks') &&
            !lowerTitle.contains('repack updated') &&
            !links.contains(link)) {
          links.add(link);
        }
      }

      // Fetch details in parallel batches, yield in popularity order.
      const batchSize = 4;
      for (var i = 0; i < links.length; i += batchSize) {
        final batch = links.skip(i).take(batchSize).map(getGameDetails);
        for (final game in await Future.wait(batch)) {
          // Keep the real genres: they are needed for the NSFW filter.
          if (game != null) yield game;
        }
      }
    } catch (e) {
      debugPrint('Error streaming popular games: $e');
    }
  }

  // Newest-first post URLs gathered from the sitemaps, for paging.
  List<String>? _sitemapUrls;
  int _sitemapCursor = 0;
  final List<String> _recentPostUrls = [];

  Future<void> _ensureRecentPosts(int needed) async {
    if (_sitemapUrls == null) {
      final indexResponse = await _web.get(Uri.parse(_sitemapIndexUrl));
      if (indexResponse.statusCode != 200) {
        throw Exception('Failed to load sitemap index');
      }
      final indexDoc = XmlDocument.parse(indexResponse.body);
      final locs = indexDoc
          .findAllElements('sitemap')
          .map((n) => n.findElements('loc').firstOrNull?.innerText)
          .whereType<String>()
          .where((loc) => loc.contains('post-sitemap'))
          .toList();
      locs.sort(
        (a, b) => _extractSitemapIndex(b).compareTo(_extractSitemapIndex(a)),
      );
      _sitemapUrls = locs;
    }

    final seen = _recentPostUrls.toSet();
    while (_recentPostUrls.length < needed &&
        _sitemapCursor < _sitemapUrls!.length) {
      final mapResponse = await _web.get(
        Uri.parse(_sitemapUrls![_sitemapCursor++]),
      );
      if (mapResponse.statusCode != 200) continue;
      final mapDoc = XmlDocument.parse(mapResponse.body);
      final urls = mapDoc
          .findAllElements('url')
          .map((n) => n.findElements('loc').firstOrNull?.innerText)
          .whereType<String>()
          .toList()
          .reversed;
      for (final loc in urls) {
        if (loc.contains('updates-digest') ||
            loc.contains('upcoming-repacks') ||
            loc.contains('repack-updated') ||
            loc.trim() == '$_baseUrl/' ||
            seen.contains(loc)) {
          continue;
        }
        seen.add(loc);
        _recentPostUrls.add(loc);
      }
    }
  }

  /// Streams newly added games, newest first. Use [offset] to page.
  /// Pages are fetched in parallel but yielded in order.
  Stream<Game> streamNewlyAddedGames({int offset = 0, int count = 12}) async* {
    try {
      if (offset == 0) {
        _sitemapUrls = null;
        _sitemapCursor = 0;
        _recentPostUrls.clear();
      }
      await _ensureRecentPosts(offset + count);
      final slice = _recentPostUrls.skip(offset).take(count).toList();

      const batchSize = 4;
      for (var i = 0; i < slice.length; i += batchSize) {
        final batch = slice.skip(i).take(batchSize).map(getGameDetails);
        for (final game in await Future.wait(batch)) {
          if (game == null) continue;
          final lowerTitle = game.title.toLowerCase();
          if (lowerTitle.contains('upcoming repacks') ||
              lowerTitle.contains('repack updated')) {
            continue;
          }
          yield game;
        }
      }
    } catch (e) {
      debugPrint('Error streaming newly added games: $e');
    }
  }

  /// Whether more "newly added" pages may be available after [loaded] posts.
  bool hasMoreNewlyAdded(int loaded) =>
      loaded < _recentPostUrls.length ||
      _sitemapCursor < (_sitemapUrls?.length ?? 1);

  int _extractSitemapIndex(String url) {
    // Extract number from post-sitemapX.xml
    final RegExp regex = RegExp(r'post-sitemap(\d+)\.xml');
    final match = regex.firstMatch(url);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    // post-sitemap.xml (no number) is effectively 0 (the first one)
    return 0;
  }

  /// Scrapes details for a single game page (cached for a few minutes).
  Future<Game?> getGameDetails(String url) async {
    final cached = _detailsCache[url];
    if (cached != null && DateTime.now().difference(cached.$1) < _detailsTtl) {
      return cached.$2;
    }
    final game = await _fetchGameDetails(url);
    if (game != null) {
      _detailsCache[url] = (DateTime.now(), game);
      unawaited(CacheStore().writeGame(game));
    }
    return game;
  }

  Future<Game?> _fetchGameDetails(String url) async {
    debugPrint('ScraperService: Fetching $url');
    try {
      final response = await _web.get(Uri.parse(url));
      debugPrint(
        'ScraperService: Response status for $url: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        debugPrint('ScraperService: Failed with status ${response.statusCode}');
        return null;
      }

      final document = parser.parse(response.body);
      debugPrint('ScraperService: Document parsed');

      final content = document.querySelector('.entry-content');
      if (content == null) {
        debugPrint('ScraperService: content is null');
      }

      // Title
      final title =
          document.querySelector('.entry-title')?.text.trim() ??
          'Unknown Title';

      // Cover URL
      final coverNode =
          content?.querySelector('img.alignleft') ??
          content?.querySelector('img');
      final coverUrl = coverNode?.attributes['src'] ?? '';

      // Size
      // Extract from "Original Size: ... Repack Size: ..." text usually in the first paragraph or generic text
      // FitGirl site structure varies, often: "<h3>...</h3> <p>... <strong>Repack Size:</strong> ...</p>"
      // Size and Detail Extraction
      // Structure: Original Size: <strong>...</strong>, Repack Size: <strong>...</strong>
      String size = 'TBD';
      String? originalSize;
      String? repackSize;
      String? companies;
      String? languages;

      final htmlContent = content?.innerHtml ?? '';
      final bodyText = content?.text ?? '';

      // Original Size
      final originalSizeMatch = RegExp(
        r'Original Size:\s*<strong>(.*?)</strong>',
        caseSensitive: false,
      ).firstMatch(htmlContent);
      if (originalSizeMatch != null) {
        originalSize = originalSizeMatch.group(1)?.trim();
      }

      // Repack Size
      final repackSizeMatch = RegExp(
        r'Repack Size:\s*<strong>(.*?)</strong>',
        caseSensitive: false,
      ).firstMatch(htmlContent);
      if (repackSizeMatch != null) {
        repackSize = repackSizeMatch.group(1)?.trim(); // E.g. "from 51.1 GB"
        size = repackSize!; // Use repack size as main size
      }

      // Companies
      final companiesMatch = RegExp(
        r'Companies:\s*<strong>(.*?)</strong>',
        caseSensitive: false,
      ).firstMatch(htmlContent);
      if (companiesMatch != null) {
        companies = companiesMatch.group(1)?.trim();
      }

      // Languages
      final languagesMatch = RegExp(
        r'Languages:\s*<strong>(.*?)</strong>',
        caseSensitive: false,
      ).firstMatch(htmlContent);
      if (languagesMatch != null) {
        languages = languagesMatch.group(1)?.trim();
      }

      // Genre / Tags
      // Usually "Genres/Tags: ..."
      String? genre;
      final genreMatch = RegExp(
        r'Genres/Tags:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(bodyText);
      if (genreMatch != null) {
        genre = genreMatch.group(1)?.trim();
      }

      // Description Extraction
      String description = '';
      if (content != null) {
        final buffer = StringBuffer();

        for (var node in content.nodes) {
          // Stop if we hit the Download Mirrors section
          if (node is Element &&
              node.localName == 'h3' &&
              (node.text.contains('Download Mirrors') ||
                  node.text.contains('Direct Links'))) {
            break;
          }

          final text = node.text?.trim() ?? '';
          if (text.isEmpty) continue;

          // Skip known non-description blocks
          if (text.contains('Genres/Tags:') ||
              text.contains('Repack Size:') ||
              text.contains('Original Size:') ||
              text.contains('Company:')) {
            continue;
          }

          // Skip headers (Title is usually H3)
          if (node is Element && node.localName == 'h3') {
            continue;
          }

          buffer.write('$text\n\n');
        }
        description = buffer.toString().trim();

        // Fallback: If description is empty, try to find "Repack Features"
        if (description.isEmpty) {
          final headers = content.querySelectorAll('h3');
          for (var header in headers) {
            if (header.text.contains('Repack Features')) {
              var next = header.nextElementSibling;
              if (next != null && next.localName == 'ul') {
                description = 'Repack Features:\n';
                for (var li in next.querySelectorAll('li')) {
                  description += '• ${li.text.trim()}\n';
                }
              }
              break;
            }
          }
        }
      }

      // Download Links
      String? magnetLink;
      String? torrentUrl;
      Map<String, String> mirrors = {};

      if (content != null) {
        // Find Magnet
        final magnetNode = content.querySelector('a[href^="magnet:?"]');
        magnetLink = magnetNode?.attributes['href'];

        // Find Torrent File (.torrent)
        final torrentNode = content.querySelector('a[href*=".torrent"]');
        torrentUrl = torrentNode?.attributes['href'];

        // Find Mirrors (FuckingFast, DataNodes, etc.)
        final links = content.querySelectorAll('a');
        List<String> directFuckingFast = [];
        List<String> directDataNodes = [];

        for (var link in links) {
          var href = link.attributes['href'];
          final text = link.text.trim();

          if (href == null) continue;

          // Normalize URL: Ensure it has a scheme
          if (href.startsWith('//')) {
            href = 'https:$href';
          }

          if (href.contains('fuckingfast.co')) {
            directFuckingFast.add(href);
          } else if (text.contains('FuckingFast')) {
            if (directFuckingFast.isEmpty) mirrors['FuckingFast'] = href;
          } else if (href.contains('datanodes.to')) {
            directDataNodes.add(href);
          } else if (text.contains('DataNodes') || href.contains('datanodes')) {
            if (directDataNodes.isEmpty) mirrors['DataNodes'] = href;
          } else if (text.contains('MultiUpload') ||
              href.contains('multiupload')) {
            mirrors['MultiUpload'] = href;
          } else if (text.contains('1337x')) {
            mirrors['1337x'] = href;
          } else if (text.contains('RuTor')) {
            mirrors['RuTor'] = href;
          }
        }

        if (directFuckingFast.isNotEmpty) {
          mirrors['FuckingFast'] = directFuckingFast.join('\n');
        }
        if (directDataNodes.isNotEmpty) {
          mirrors['DataNodes'] = directDataNodes.join('\n');
        }
      }

      // Screenshots logic
      List<String> screenshots = [];
      try {
        final headers = document.querySelectorAll('h3');
        for (var header in headers) {
          if (header.text.contains('Screenshots')) {
            var nextElement = header.nextElementSibling;
            // The structure is typically <h3>Screenshots</h3> <p> ... images ... </p>
            // We search for the next <p> tag.
            while (nextElement != null &&
                nextElement.localName != 'p' &&
                nextElement.localName != 'h3') {
              nextElement = nextElement.nextElementSibling;
            }

            if (nextElement != null && nextElement.localName == 'p') {
              final imgs = nextElement.querySelectorAll('img');
              for (var img in imgs) {
                final src = img.attributes['src'];
                if (src != null && src.isNotEmpty) {
                  screenshots.add(src);
                }
              }
            }
            break;
          }
        }
      } catch (e) {
        debugPrint('Error extracting screenshots: $e');
      }

      // Upload Date
      String? uploadDate;
      final dateNode = document.querySelector('.entry-date time');
      if (dateNode != null) {
        uploadDate = dateNode.text.trim();
      }

      return Game(
        id: url,
        url: url,
        title: title,
        coverUrl: coverUrl,
        size: size,
        originalSize: originalSize,
        repackSize: repackSize,
        companies: companies,
        languages: languages,
        genre: genre,
        uploadDate: uploadDate,
        description: description,
        magnetLink: magnetLink,
        torrentUrl: torrentUrl,
        mirrors: mirrors,
        screenshots: screenshots,
      );
    } catch (e) {
      debugPrint('Failed to scrape details for $url: $e');
      return null;
    }
  }

  /// Search for games matching the query
  Future<List<Game>> searchGames(String query) async {
    debugPrint('ScraperService: Searching for "$query"');
    try {
      final url = '$_baseUrl/?s=${Uri.encodeComponent(query)}';
      final response = await _web.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('Failed to load search results');
      }

      final document = parser.parse(response.body);
      final games = <Game>[];

      // Select articles - FitGirl uses standard WP structure
      // Typically <article class="post ...">
      final articles = document.querySelectorAll('article.post');

      final queryParts = query
          .toLowerCase()
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();
      final validLinks = <String>[];

      for (var article in articles) {
        final titleElement = article.querySelector('.entry-title a');
        final link = titleElement?.attributes['href'];
        final title = titleElement?.text.trim() ?? 'Unknown Title';

        if (link != null) {
          final lowerTitle = title.toLowerCase();

          // 1. Filter notice posts
          // Exclude "Trailer" posts and other administrative posts
          if (lowerTitle.contains('upcoming repacks') ||
              lowerTitle.contains('repack updated') ||
              lowerTitle.contains('trailer')) {
            continue;
          }

          // 2. AND Logic
          bool matchesAll = true;
          for (var part in queryParts) {
            if (!lowerTitle.contains(part)) {
              matchesAll = false;
              break;
            }
          }

          if (matchesAll) {
            validLinks.add(link);
          }
        }
      }

      // Fetch details in parallel (Top 10 to avoid timeouts)
      final futures = validLinks.take(10).map((url) => getGameDetails(url));
      final results = await Future.wait(futures);

      for (var game in results) {
        // Strict filtering: Only show games with a valid size
        // valid repacks will always have a parsed size, whereas news/trailers won't.
        if (game != null && game.size != 'TBD') {
          games.add(game);
        }
      }
      return games;
    } catch (e) {
      debugPrint('Error searching games: $e');
      return [];
    }
  }

  /// Fetches file list from a mirror/pastebin page
  Future<List<String>> getMirrorFileList(String url) async {
    debugPrint('ScraperService: Fetching file list from $url');
    try {
      final response = await _web.get(Uri.parse(url));

      if (response.statusCode != 200) {
        return [];
      }

      final document = parser.parse(response.body);
      final links = <String>[];

      // Select all links
      final aTags = document.querySelectorAll('a');
      for (var a in aTags) {
        final href = a.attributes['href'];
        if (href != null &&
            (href.endsWith('.rar') ||
                href.endsWith('.zip') ||
                href.endsWith('.7z') ||
                href.contains('.part'))) {
          links.add(href);
        }
      }

      // If no extension-based links found, maybe try to be more generous if it's a known pastebin
      if (links.isEmpty) {
        // Fallback: look for any link that isn't a navigation link
        for (var a in aTags) {
          final href = a.attributes['href'];
          if (href != null &&
              !href.startsWith('/') &&
              !href.contains('fitgirl-repacks.site')) {
            links.add(href);
          }
        }
      }

      return links;
    } catch (e) {
      debugPrint('Error scraping file list: $e');
      return [];
    }
  }

  /// Resolves a mirror page (FuckingFast, DataNodes) to a direct download
  /// link. Throws [MirrorException] with a user-readable reason on failure.
  Future<ResolvedLink?> getDirectDownloadLink(String url) async {
    debugPrint('ScraperService: Extracting direct link for $url');
    if (url.contains('fuckingfast.co')) {
      return _viaHttpThenBrowser(
        'FuckingFast',
        http: () async => ResolvedLink(await _getFuckingFastLink(url) ?? '', {
          'Referer': 'https://fuckingfast.co/',
        }),
        browser: () => BrowserResolver().resolve(
          pageUrl: _fuckingFastPage(url),
          readyJs: _fuckingFastReadyJs,
          extractJs: _fuckingFastExtractJs,
          captureHosts: const {'dl.fuckingfast.co'},
        ),
      );
    } else if (url.contains('datanodes.to')) {
      return _viaHttpThenBrowser(
        'DataNodes',
        http: () async => ResolvedLink(await _getDataNodesLink(url) ?? '', {
          'Referer': 'https://datanodes.to/',
        }),
        browser: () => BrowserResolver().resolve(
          pageUrl: url.trim(),
          readyJs: _cloudflarePassedJs,
          extractJs: _dataNodesExtractJs(url),
          extractTimeout: const Duration(minutes: 2),
        ),
      );
    }
    return null;
  }

  /// Plain HTTP first (fast); file hosts behind Cloudflare challenge that,
  /// so fall back to a real browser engine where available.
  Future<ResolvedLink> _viaHttpThenBrowser(
    String host, {
    required Future<ResolvedLink> Function() http,
    required Future<ResolvedLink> Function() browser,
  }) async {
    MirrorException httpError;
    try {
      final link = await http();
      if (link.url.startsWith('http')) return link;
      httpError = MirrorException('$host did not return a download link');
    } on MirrorException catch (e) {
      if (e.permanent) rethrow;
      httpError = e;
    } catch (e) {
      httpError = MirrorException('Could not reach $host: $e');
    }
    if (!BrowserResolver.isSupported) {
      throw MirrorException(
        '${httpError.message}. $host blocks apps with a browser check; '
        'use the other mirror or the torrent',
      );
    }
    try {
      return await browser();
    } on BrowserException catch (e) {
      final removed = e.message.contains('removed');
      throw MirrorException('$host: ${e.message}', permanent: removed);
    }
  }

  static String _fuckingFastPage(String url) {
    final segments = Uri.parse(
      url.trim(),
    ).pathSegments.where((s) => s.isNotEmpty).toList();
    final id = segments.first == 'f' && segments.length > 1
        ? segments[1]
        : segments.first;
    return 'https://fuckingfast.co/$id';
  }

  /// Cloudflare's check is done once the real page is there.
  static const _cloudflarePassedJs =
      "document.readyState === 'complete' && "
      "!/just a moment|attention required/i.test(document.title) && "
      "!document.querySelector('#challenge-form, #challenge-stage, "
      "iframe[src*=\"challenges.cloudflare.com\"]:not([style*=\"display: none\"])')";

  static const _fuckingFastReadyJs =
      "document.querySelector('[hx-post*=\"/go\"]') !== null || "
      "(document.readyState === 'complete' && "
      "/not found|deleted|removed|no longer/i.test(document.body.innerText.slice(0, 2000)))";

  /// POST the button's htmx endpoint and read HX-Redirect; if that doesn't
  /// answer, click the real button (the redirect to dl.* is captured).
  static const _fuckingFastExtractJs = r'''
(async () => {
  const send = (o) => FGBridge.postMessage(JSON.stringify(o));
  try {
    const btn = document.querySelector('[hx-post*="/go"]');
    if (!btn) {
      send({error: 'File was removed from FuckingFast'});
      return;
    }
    const r = await fetch(btn.getAttribute('hx-post'), {
      method: 'POST',
      credentials: 'include',
      headers: {'HX-Request': 'true', 'HX-Current-URL': location.href},
    });
    const link = r.headers.get('HX-Redirect');
    if (link) { send({url: link}); return; }
    btn.click();
    setTimeout(() => btn.click(), 1500);
  } catch (e) {
    send({error: String(e)});
  }
})();
''';

  /// Step 1 (`download1`), then step 2: a Cloudflare Turnstile check and a
  /// countdown before `download2` answers with JSON `{url}`. The check runs
  /// in an overlay; it usually passes by itself, and if it wants a tap the
  /// page is shown (`{show: true}`).
  static String _dataNodesExtractJs(String fileUrl) {
    final segments = Uri.parse(
      fileUrl.trim(),
    ).pathSegments.where((s) => s.isNotEmpty).toList();
    final code = segments.isEmpty ? '' : segments.first;
    final name = segments.length > 1 ? segments.last : '';
    return _dataNodesJs
        .replaceAll('__CODE__', jsonEncode(code))
        .replaceAll('__FNAME__', jsonEncode(name));
  }

  @visibleForTesting
  static String dataNodesExtractJsForTest(String fileUrl) =>
      _dataNodesExtractJs(fileUrl);

  static const _dataNodesJs = r'''
(async () => {
  const send = (o) => FGBridge.postMessage(JSON.stringify(o));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const removed = (t) => /file not found|file was removed|no such file|file has been deleted/i.test(t);
  try {
    if (removed(document.body ? document.body.innerText : '')) {
      send({error: 'File was removed from DataNodes'});
      return;
    }
    const endpoint = location.origin + '/download';

    // Step 1 of 2: the "Continue to Download" form.
    const step1 = new URLSearchParams({
      op: 'download1', usr_login: '', id: __CODE__, fname: __FNAME__,
      referer: '', method_free: 'Free Download >>',
    });
    const form = document.getElementById('downloadForm');
    if (form) for (const [k, v] of new FormData(form)) step1.set(k, v);
    const r1 = await fetch(endpoint, {method: 'POST', body: step1, credentials: 'include'});
    const startedAt = Date.now();
    const html = await r1.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const dc = doc.querySelector('download-countdown');
    if (!dc) {
      send({error: removed(doc.body ? doc.body.innerText : html)
        ? 'File was removed from DataNodes'
        : 'DataNodes changed its download page'});
      return;
    }
    const attr = (n, d = '') => dc.getAttribute(n) ?? d;

    // Step 2 of 2: a captcha (Cloudflare Turnstile) and a countdown.
    const extra = {};
    const captchaHtml = attr('captcha-html');
    if (attr(':has-captcha') === 'true' && captchaHtml) {
      const key = /data-sitekey=["']([^"']+)/.exec(captchaHtml);
      if (!/cf-turnstile/.test(captchaHtml) || !key) {
        send({error: 'DataNodes asks for a captcha the app cannot show'});
        return;
      }
      extra['cf-turnstile-response'] = await new Promise((resolve, reject) => {
        // Full-page overlay so only the check is visible if a tap is needed.
        const box = document.createElement('div');
        box.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#121212;' +
          'display:flex;flex-direction:column;align-items:center;justify-content:center;' +
          'gap:16px;color:#ddd;font:15px sans-serif;text-align:center;padding:16px';
        box.innerHTML = '<div>DataNodes needs a quick check before the download</div>';
        const slot = document.createElement('div');
        box.appendChild(slot);
        document.body.appendChild(box);
        let shown = false;
        const show = () => { if (!shown) { shown = true; send({show: true}); } };
        const timer = setTimeout(show, 20000);
        const render = () => {
          try {
            window.turnstile.render(slot, {
              sitekey: key[1],
              callback: (token) => {
                clearTimeout(timer);
                if (shown) send({show: false});
                box.remove();
                resolve(token);
              },
              'before-interactive-callback': show,
              'error-callback': () => { show(); },
            });
          } catch (e) { reject(e); }
        };
        if (window.turnstile) { render(); return; }
        const s = document.createElement('script');
        s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
        s.onload = render;
        s.onerror = () => reject(new Error('Could not load the DataNodes check'));
        document.head.appendChild(s);
      });
    }
    const wait = parseInt(attr(':countdown', '0'), 10) || 0;
    const left = startedAt + (wait + 1) * 1000 - Date.now();
    if (left > 0) await sleep(left);

    const body = new FormData();
    body.append('op', 'download2');
    body.append('id', attr('code', __CODE__));
    body.append('rand', attr('rand'));
    body.append('referer', attr('referer'));
    body.append('method_free', attr('free-method', 'Free Download >>'));
    body.append('method_premium', attr('premium-method'));
    body.append('g_captch__a', '1');
    if (attr('dl-token')) body.append('dl_token', attr('dl-token'));
    for (const k in extra) body.append(k, extra[k]);
    const r2 = await fetch(endpoint, {
      method: 'POST', body, credentials: 'include',
      headers: {'X-Dn-Dl': '1'}, redirect: 'manual',
    });
    let j = null;
    try { j = JSON.parse(await r2.text()); } catch (_) {}
    if (j && j.url) { send({url: decodeURIComponent(j.url)}); return; }
    send({error: j && j.error ? 'DataNodes: ' + j.error : 'DataNodes did not return a download link'});
  } catch (e) {
    send({error: String(e && e.message || e)});
  }
})();
''';

  /// Other mirrors of the same file, matched by file name, taken from the
  /// game page (e.g. the FuckingFast copy of a DataNodes file).
  Future<List<String>> findAlternateMirrors(
    String gameUrl,
    String fileUrl,
  ) async {
    final game = await getGameDetails(gameUrl);
    if (game == null) return const [];
    return alternateMirrorsIn(game, fileUrl);
  }

  /// Same as [findAlternateMirrors] for an already loaded [game].
  static List<String> alternateMirrorsIn(Game game, String fileUrl) {
    final name = fileNameFromUrl(fileUrl).toLowerCase();
    if (name.isEmpty) return const [];
    final result = <String>[];
    for (final list in game.mirrors.values) {
      for (final candidate in list.split('\n')) {
        final c = candidate.trim();
        if (c.isEmpty || c == fileUrl.trim()) continue;
        if (fileNameFromUrl(c).toLowerCase() == name) result.add(c);
      }
    }
    // Prefer FuckingFast: no captcha and the fastest servers.
    int rank(String u) => u.contains('fuckingfast') ? 0 : 1;
    result.sort((a, b) => rank(a).compareTo(rank(b)));
    return result;
  }

  /// Helper to extract URL from window.open() calls (older page layouts).
  String? _extractWindowOpenUrl(String html) {
    final regex = RegExp(r'''window\.open\(.*?['"](https?://[^\s'")]+)['"]''');
    final match = regex.firstMatch(html);
    return match?.group(1);
  }

  /// FuckingFast: the DOWNLOAD button POSTs to `/f/<id>/go` and the direct
  /// link comes back in the HX-Redirect header (htmx).
  Future<String?> _getFuckingFastLink(String url) async {
    final uri = Uri.parse(url.trim());
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw const MirrorException('Invalid FuckingFast link');
    }
    final id = segments.first == 'f' && segments.length > 1
        ? segments[1]
        : segments.first;
    final page = 'https://fuckingfast.co/$id';

    final res = await _web.post(
      Uri.parse('https://fuckingfast.co/f/$id/go'),
      headers: {
        'HX-Request': 'true',
        'HX-Current-URL': page,
        'Referer': page,
        'Origin': 'https://fuckingfast.co',
      },
    );
    if (res.statusCode == 404) {
      throw const MirrorException(
        'File was removed from FuckingFast',
        permanent: true,
      );
    }
    final link = res.headers['hx-redirect'];
    if (link != null && link.startsWith('http')) return link;

    // Older layout: the link was embedded in the page.
    final html = (await _web.get(Uri.parse(page))).body;
    final legacy =
        _extractWindowOpenUrl(html) ??
        RegExp(
          r'https://(?:dl\.)?fuckingfast\.co/dl/[A-Za-z0-9_-]+',
        ).firstMatch(html)?.group(0);
    if (legacy != null) return legacy;
    throw MirrorException(
      'FuckingFast did not return a download link (HTTP ${res.statusCode})',
    );
  }

  static bool _dataNodesRemoved(String body) => RegExp(
    r'file not found|file was removed|no such file|file has been deleted',
    caseSensitive: false,
  ).hasMatch(body);

  /// DataNodes over plain HTTP: the same two steps as [_dataNodesJs]. Only
  /// works while step 2 has no captcha; otherwise the browser takes over.
  Future<String?> _getDataNodesLink(String url) async {
    final fileUri = Uri.parse(url.trim());
    final segments = fileUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw const MirrorException('Invalid DataNodes link');
    }
    final code = segments.first;
    final fileName = segments.length > 1 ? segments.last : '';
    const download = 'https://datanodes.to/download';
    const removed = MirrorException(
      'File was removed from DataNodes',
      permanent: true,
    );
    final headers = {'Origin': 'https://datanodes.to', 'Referer': download};

    // The file page sets the session cookies.
    final page = await _web.get(fileUri);
    if (page.statusCode == 404 || _dataNodesRemoved(page.body)) throw removed;

    final step1 = await _web.post(
      Uri.parse(download),
      headers: headers,
      fields: {
        'op': 'download1',
        'usr_login': '',
        'id': code,
        'fname': fileName,
        'referer': '',
        'method_free': 'Free Download >>',
      },
    );
    final startedAt = DateTime.now();
    if (step1.statusCode == 404 || _dataNodesRemoved(step1.body)) {
      throw removed;
    }
    final step2 = parser.parse(step1.body).querySelector('download-countdown');
    if (step2 == null) {
      throw MirrorException(
        'DataNodes changed its download page (HTTP ${step1.statusCode})',
      );
    }
    String attr(String name, [String fallback = '']) =>
        step2.attributes[name] ?? fallback;
    if (attr(':has-captcha') == 'true') {
      throw const MirrorException('DataNodes asks for a browser check');
    }
    final wait = int.tryParse(attr(':countdown')) ?? 0;
    final left = startedAt
        .add(Duration(seconds: wait + 1))
        .difference(DateTime.now());
    if (wait > 0 && !left.isNegative) await Future<void>.delayed(left);

    final res = await _web.post(
      Uri.parse(download),
      multipart: true,
      headers: {...headers, 'X-Dn-Dl': '1'},
      fields: {
        'op': 'download2',
        'id': attr('code', code),
        'rand': attr('rand'),
        'referer': attr('referer'),
        'method_free': attr('free-method', 'Free Download >>'),
        'method_premium': attr('premium-method'),
        'g_captch__a': '1',
        if (attr('dl-token').isNotEmpty) 'dl_token': attr('dl-token'),
      },
    );
    final link = _dataNodesLinkFrom(res);
    if (link != null) return link;
    String? error;
    try {
      final data = jsonDecode(res.body);
      if (data is Map && data['error'] is String) error = data['error'];
    } catch (_) {}
    throw MirrorException(
      error != null
          ? 'DataNodes: $error'
          : 'DataNodes did not return a download link (HTTP ${res.statusCode})',
    );
  }

  String? _dataNodesLinkFrom(http.Response res) {
    // JSON {"url": "<percent-encoded link>"}
    try {
      final data = jsonDecode(res.body);
      if (data is Map && data['url'] is String) {
        final link = Uri.decodeFull(data['url'] as String);
        if (link.startsWith('http')) return link;
      }
    } catch (_) {}
    // Redirect straight to a file server (not back to the site itself).
    final location = res.headers['location'];
    if (location != null &&
        location.startsWith('http') &&
        !Uri.parse(location).host.endsWith('datanodes.to')) {
      return location;
    }
    return null;
  }

  /// Extracts FuckingFast/DataNodes links from a Pastebin page (e.g., pastefg.hermietkreeft.site)
  Future<List<String>> getPastebinLinks(String url) async {
    debugPrint('ScraperService: Fetching pastebin links from $url');
    try {
      final response = await _web.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        },
      );

      debugPrint(
        'ScraperService: Pastebin response status: ${response.statusCode}, body length: ${response.body.length}',
      );

      if (response.statusCode != 200) {
        return [];
      }

      final document = parser.parse(response.body);
      final links = <String>[];

      // Select all links
      final aTags = document.querySelectorAll('a');
      for (var a in aTags) {
        var href = a.attributes['href'];
        if (href != null) {
          // Normalize
          if (href.startsWith('//')) {
            href = 'https:$href';
          }
          // Handle relative paths? Usually these pastebins use absolute or protocol-relative.

          // Check for FuckingFast or DataNodes
          if (href.contains('fuckingfast.co') ||
              href.contains('datanodes.to')) {
            // Avoid duplicates
            if (!links.contains(href)) {
              links.add(href);
            }
          }
        }
      }

      // Fallback: search in text content if no <a> tags found (sometimes plain text)
      // (This is less likely for clickable links but possible for simple pastes)
      if (links.isEmpty) {
        debugPrint(
          'ScraperService: No <a> tags matches found, checking raw text...',
        );
        final regex = RegExp(
          r'(https?://(fuckingfast\.co|datanodes\.to)/[^\s"<>]+)',
        );
        final matches = regex.allMatches(response.body);
        for (var m in matches) {
          final link = m.group(0);
          if (link != null && !links.contains(link)) {
            links.add(link);
          }
        }
      }

      debugPrint('ScraperService: Found ${links.length} links');
      return links;
    } catch (e) {
      debugPrint('Error scraping pastebin links: $e');
      return [];
    }
  }
}

/// A mirror could not provide a download link. [message] is shown to the
/// user; [permanent] means retrying the same link is pointless.
class MirrorException implements Exception {
  final String message;
  final bool permanent;
  const MirrorException(this.message, {this.permanent = false});

  @override
  String toString() => message;
}
