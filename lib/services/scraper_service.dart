import 'package:fitgirl_mobile_flutter/services/web_client.dart';
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
          if (game != null) yield game.copyWith(genre: 'Popular');
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
    if (game != null) _detailsCache[url] = (DateTime.now(), game);
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

  /// Extracts the direct download link from a supported mirror (FuckingFast, DataNodes)
  Future<String?> getDirectDownloadLink(String url) async {
    debugPrint('ScraperService: Extracting direct link for $url');
    if (url.contains('fuckingfast.co')) {
      return _getFuckingFastLink(url);
    } else if (url.contains('datanodes.to')) {
      return _getDataNodesLink(url);
    }
    return null;
  }

  /// Helper to extract URL from window.open() calls (Ported from Python UniversalExtractor)
  String? _extractWindowOpenUrl(String html) {
    // Regex matches: window.open("http..." or window.open('http...'
    // Using triple-quote raw string to safely allow both ' and "
    final regex = RegExp(r'''window\.open\(.*?['"](https?://[^\s'")]+)['"]''');
    final match = regex.firstMatch(html);
    return match?.group(1);
  }

  Future<String?> _getFuckingFastLink(String url) async {
    try {
      final response = await _web.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
      );

      // Try robust window.open finding (Python Logic)
      final directLink = _extractWindowOpenUrl(response.body);
      if (directLink != null) return directLink;

      // Fallback to specific FF regex if generic fails
      final regex = RegExp(r'https://fuckingfast.co/dl/[a-zA-Z0-9_-]+');
      final match = regex.firstMatch(response.body);
      return match?.group(0);
    } catch (e) {
      debugPrint('Error parsing FuckingFast link: $e');
    }
    return null;
  }

  Future<String?> _getDataNodesLink(String url) async {
    try {
      final response = await _web.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
      );

      // 1. Try generic window.open matching (Python Fallback Logic)
      final directLink = _extractWindowOpenUrl(response.body);
      if (directLink != null) return directLink;

      // 2. Try extraction from "Download" button if present (Python Logic)
      // Python: soup.find('a', class_='download-btn')
      // Regex for <a href="..." class="download-btn">
      final btnRegex = RegExp(
        r'''<a\s+(?:[^>]*?\s+)?href=['"](https?://[^'"]+)['"][^>]*?class=['"][^'"]*download-btn[^'"]*['"]''',
      );
      final btnMatch = btnRegex.firstMatch(response.body);
      if (btnMatch != null) return btnMatch.group(1);
    } catch (e) {
      debugPrint('Error parsing DataNodes link: $e');
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
