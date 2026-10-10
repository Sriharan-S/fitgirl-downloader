import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:http/http.dart' as http;

/// HTTP client for scraping that behaves like a polite browser.
///
/// FitGirl sits behind DDoS-Guard, which answers bursts of requests with a
/// "set cookies and redirect to the same URL" check. A plain `http.get`
/// follows that redirect without the cookies and loops until it gives up, so
/// every page fails. This client:
/// - keeps cookies per host and follows redirects itself, sending them back;
/// - sends browser-like headers;
/// - limits how many requests run at once;
/// - retries timeouts, network errors, 429 and 5xx responses with backoff.
class WebClient {
  WebClient({http.Client? inner, this.maxConcurrent = 2})
    : _inner = inner ?? http.Client();

  final http.Client _inner;
  final int maxConcurrent;

  final Map<String, Map<String, String>> _cookies = {}; // host -> name=value
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int retries = 2,
  }) async {
    await _acquire();
    try {
      for (var attempt = 0; ; attempt++) {
        try {
          final res = await _getFollowingRedirects(
            url,
            headers,
          ).timeout(timeout);
          final retryable = res.statusCode == 429 || res.statusCode >= 500;
          if (retryable && attempt < retries) {
            await _backoff(attempt);
            continue;
          }
          return res;
        } on Exception catch (e) {
          final retryable =
              e is TimeoutException ||
              e is SocketException ||
              e is HttpException ||
              e is http.ClientException;
          if (!retryable || attempt >= retries) rethrow;
          await _backoff(attempt);
        }
      }
    } finally {
      _release();
    }
  }

  Future<http.Response> _getFollowingRedirects(
    Uri url,
    Map<String, String>? headers,
  ) async {
    var uri = url;
    for (var hop = 0; hop < 10; hop++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({..._browserHeaders, ...?headers});
      final cookie = _cookieHeader(uri.host);
      if (cookie != null) request.headers['Cookie'] = cookie;

      final response = await http.Response.fromStream(
        await _inner.send(request),
      );
      _storeCookies(uri.host, response);

      final location = response.headers['location'];
      if (_isRedirect(response.statusCode) && location != null) {
        uri = uri.resolve(location);
        continue;
      }
      return response;
    }
    throw http.ClientException('Too many redirects', url);
  }

  static bool _isRedirect(int code) =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  String? _cookieHeader(String host) {
    final jar = _cookies[host];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _storeCookies(String host, http.Response response) {
    final values = response.headersSplitValues['set-cookie'];
    if (values == null) return;
    final jar = _cookies.putIfAbsent(host, () => {});
    for (final raw in values) {
      final pair = raw.split(';').first;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      jar[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
  }

  Future<void> _backoff(int attempt) =>
      Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future; // Slot handed over by _release
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
