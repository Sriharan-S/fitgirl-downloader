import 'package:http/http.dart' as http;
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

  /// Streams popular games one by one
  Stream<Game> streamPopularGames() async* {
    try {
      final response = await http.get(Uri.parse(_popularUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to load popular games');
      }

      final document = parser.parse(response.body);
      final elements = document.querySelectorAll('.bump-view');

      // Limit to first 10 popular games
      final topElements = elements.take(10);

      for (var element in topElements) {
        final link = element.attributes['href'];
        final title = element.attributes['title'] ?? 'Unknown Title';

        if (link != null && link.contains('fitgirl-repacks.site')) {
          final lowerTitle = title.toLowerCase();
          if (!lowerTitle.contains('upcoming repacks') &&
              !lowerTitle.contains('repack updated')) {
            try {
              final gameDetails = await getGameDetails(link);
              if (gameDetails != null) {
                yield gameDetails.copyWith(genre: 'Popular');
              }
            } catch (e) {
              print('Error fetching popular game details for $title: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error streaming popular games: $e');
    }
  }

  /// Streams newly added games one by one
  Stream<Game> streamNewlyAddedGames() async* {
    try {
      // 1. Fetch sitemap index
      final indexResponse = await http.get(Uri.parse(_sitemapIndexUrl));
      if (indexResponse.statusCode != 200)
        throw Exception('Failed to load sitemap index');

      final indexDoc = XmlDocument.parse(indexResponse.body);
      final sitemaps = indexDoc.findAllElements('sitemap');

      // 2. Find the last post-sitemap
      final postSitemaps = sitemaps.where((node) {
        final loc = node.findElements('loc').firstOrNull?.innerText;
        return loc != null && loc.contains('post-sitemap');
      }).toList();

      String? lastPostSitemapUrl;

      if (postSitemaps.isNotEmpty) {
        postSitemaps.sort((a, b) {
          final aLoc = a.findElements('loc').first.innerText;
          final bLoc = b.findElements('loc').first.innerText;
          return _extractSitemapIndex(
            aLoc,
          ).compareTo(_extractSitemapIndex(bLoc));
        });

        lastPostSitemapUrl = postSitemaps.last
            .findElements('loc')
            .first
            .innerText;
      }

      if (lastPostSitemapUrl != null) {
        // 3. Fetch the last post sitemap
        final mapResponse = await http.get(Uri.parse(lastPostSitemapUrl));
        if (mapResponse.statusCode != 200)
          throw Exception('Failed to load post sitemap');

        final mapDoc = XmlDocument.parse(mapResponse.body);
        final urls = mapDoc.findAllElements('url');

        // 4. Get the last N URLs (stream top 10 valid ones)
        final recentUrls = urls.toList().reversed.take(15);
        final seenUrls = <String>{};
        int yieldedCount = 0;

        for (var urlNode in recentUrls) {
          if (yieldedCount >= 10) break;

          final loc = urlNode.findElements('loc').firstOrNull?.innerText;

          if (loc != null &&
              !loc.contains('updates-digest') &&
              !loc.contains('upcoming-repacks') &&
              !loc.contains('repack-updated') &&
              !seenUrls.contains(loc)) {
            seenUrls.add(loc);

            try {
              final game = await getGameDetails(loc);
              if (game != null) {
                final lowerTitle = game.title.toLowerCase();
                if (!lowerTitle.contains('upcoming repacks') &&
                    !lowerTitle.contains('repack updated')) {
                  yield game;
                  yieldedCount++;
                }
              }
            } catch (e) {
              print('Error scraping game $loc: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error streaming newly added games: $e');
    }
  }

  // Keep existing Future based methods if needed, or replace them.
  // For now, I'll keep the old ones commented out or just overwrite them if I replace the whole block.
  // The Instruction says "StartLine: 22", effectively replacing `getPopularGames` and `getNewlyAddedGames`.

  // Actually, I will just add these new methods alongside the old ones to be safe,
  // OR replace the old ones entirely if I'm sure nothing else uses them.
  // SearchScreen uses `searchGames`. DiscoverScreen uses these.
  // Since I am replacing the block from line 22 to 161 (which covers both getPopularGames and getNewlyAddedGames),
  // I am effectively REPLACING them with the streaming versions.
  // BUT the return types are different (Future<List> vs Stream), so I should rename them or update callsites.
  // I will rename them to `stream...` but maybe keep `get...` as wrappers if needed?
  // No, the user wants streaming. I'll replace them with `stream...` methods.

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

  /// Scrapes details for a single game page
  Future<Game?> getGameDetails(String url) async {
    print('ScraperService: Fetching $url');
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      print('ScraperService: Response status for $url: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('ScraperService: Failed with status ${response.statusCode}');
        return null;
      }

      final document = parser.parse(response.body);
      print('ScraperService: Document parsed');

      final content = document.querySelector('.entry-content');
      if (content == null) {
        print('ScraperService: content is null');
      }

      // Title
      final title =
          document.querySelector('.entry-title')?.text.trim() ??
          'Unknown Title';

      // Cover URL
      final coverNode =
          content?.querySelector('img.alignleft') ??
          content?.querySelector('img');
      final coverUrl =
          coverNode?.attributes['src'] ?? 'https://via.placeholder.com/300x400';

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
        print('Error extracting screenshots: $e');
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
      print('Failed to scrape details for $url: $e');
      return null;
    }
  }

  /// Search for games matching the query
  Future<List<Game>> searchGames(String query) async {
    print('ScraperService: Searching for "$query"');
    try {
      final url = '$_baseUrl/?s=${Uri.encodeComponent(query)}';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

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
      print('Error searching games: $e');
      return [];
    }
  }

  /// Fetches file list from a mirror/pastebin page
  Future<List<String>> getMirrorFileList(String url) async {
    print('ScraperService: Fetching file list from $url');
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

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
      print('Error scraping file list: $e');
      return [];
    }
  }

  /// Extracts the direct download link from a supported mirror (FuckingFast, DataNodes)
  Future<String?> getDirectDownloadLink(String url) async {
    print('ScraperService: Extracting direct link for $url');
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
      final response = await http.get(
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
      print('Error parsing FuckingFast link: $e');
    }
    return null;
  }

  Future<String?> _getDataNodesLink(String url) async {
    try {
      final response = await http.get(
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
      print('Error parsing DataNodes link: $e');
    }
    return null;
  }

  /// Extracts FuckingFast/DataNodes links from a Pastebin page (e.g., pastefg.hermietkreeft.site)
  Future<List<String>> getPastebinLinks(String url) async {
    print('ScraperService: Fetching pastebin links from $url');
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 15));

      print(
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
        print(
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

      print('ScraperService: Found ${links.length} links');
      return links;
    } catch (e) {
      print('Error scraping pastebin links: $e');
      return [];
    }
  }
}
