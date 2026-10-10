import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A direct download link plus the headers the file host expects with it.
class ResolvedLink {
  final String url;
  final Map<String, String> headers;
  const ResolvedLink(this.url, [this.headers = const {}]);
}

/// A page being worked on by [BrowserResolver]; rendered by `BrowserHost`.
class BrowserJob {
  final WebViewController controller;
  final String host;

  /// Shown to the user when the site insists on a human check.
  final ValueNotifier<bool> visible = ValueNotifier(false);
  final VoidCallback cancel;

  BrowserJob(this.controller, this.host, this.cancel);
}

class BrowserException implements Exception {
  final String message;
  const BrowserException(this.message);
  @override
  String toString() => message;
}

/// Runs file-host link extraction inside a real browser engine (Android
/// WebView / WKWebView). FuckingFast and DataNodes sit behind Cloudflare,
/// which blocks plain HTTP clients but lets browsers through; the page is
/// loaded invisibly, and only if Cloudflare asks for an interactive check is
/// it shown so the user can tap it once.
class BrowserResolver {
  static final BrowserResolver _instance = BrowserResolver._internal();
  factory BrowserResolver() => _instance;
  BrowserResolver._internal();

  static const _native = MethodChannel('fitgirl/native');

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// The job currently shown by `BrowserHost` (null when idle).
  final ValueNotifier<BrowserJob?> job = ValueNotifier(null);

  Future<void> _queue = Future.value();

  /// Loads [pageUrl], waits until [readyJs] evaluates to true (Cloudflare
  /// check passed), then runs [extractJs], which must call
  /// `FGBridge.postMessage(JSON.stringify({url}|{error}))`.
  /// Navigations to a host in [captureHosts] are intercepted and returned as
  /// the link (for sites that redirect to the file instead of answering).
  Future<ResolvedLink> resolve({
    required String pageUrl,
    required String readyJs,
    required String extractJs,
    Set<String> captureHosts = const {},
    Duration readyTimeout = const Duration(seconds: 15),
    Duration totalTimeout = const Duration(minutes: 3),
  }) {
    // One page at a time: hosts rate-limit and the user can only answer
    // one check at once.
    final run = _queue.then(
      (_) =>
          _resolve(
            pageUrl: pageUrl,
            readyJs: readyJs,
            extractJs: extractJs,
            captureHosts: captureHosts,
            readyTimeout: readyTimeout,
          ).timeout(
            totalTimeout,
            onTimeout: () => throw const BrowserException(
              'The file host did not respond in time',
            ),
          ),
    );
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<ResolvedLink> _resolve({
    required String pageUrl,
    required String readyJs,
    required String extractJs,
    required Set<String> captureHosts,
    required Duration readyTimeout,
  }) async {
    if (!isSupported) {
      throw const BrowserException('Browser check is not supported here');
    }
    final page = Uri.parse(pageUrl);
    final result = Completer<String>();
    final controller = WebViewController();
    final current = BrowserJob(controller, page.host, () {
      if (!result.isCompleted) {
        result.completeError(const BrowserException('Cancelled'));
      }
    });

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'FGBridge',
      onMessageReceived: (m) {
        if (!result.isCompleted) result.complete(m.message);
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final host = Uri.tryParse(request.url)?.host ?? '';
          if (captureHosts.any(host.endsWith)) {
            if (!result.isCompleted) {
              result.complete(jsonEncode({'url': request.url}));
            }
            return NavigationDecision.prevent;
          }
          // Stay on the file host (blocks ad pop-unders / redirects).
          final allowed =
              host.endsWith(page.host) ||
              host.endsWith('cloudflare.com') ||
              request.url.startsWith('about:');
          return allowed
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    );

    job.value = current;
    try {
      await controller.loadRequest(page);

      // Wait for the Cloudflare check to pass on its own; if it doesn't,
      // show the page so the user can complete it.
      final readySince = DateTime.now();
      while (!result.isCompleted) {
        if (await _evalBool(controller, readyJs)) break;
        if (DateTime.now().difference(readySince) > readyTimeout) {
          current.visible.value = true;
        }
        await Future.any([
          Future<void>.delayed(const Duration(milliseconds: 800)),
          result.future.then((_) {}, onError: (_) {}),
        ]);
      }
      current.visible.value = false;

      if (!result.isCompleted) await controller.runJavaScript(extractJs);
      final message =
          jsonDecode(
                await result.future.timeout(
                  const Duration(seconds: 45),
                  onTimeout: () => throw const BrowserException(
                    'The file host did not return a link',
                  ),
                ),
              )
              as Map<String, dynamic>;
      final url = message['url'] as String?;
      if (url == null || !url.startsWith('http')) {
        throw BrowserException(
          message['error'] as String? ?? 'The file host did not return a link',
        );
      }

      // Downloads must look like they come from the same browser session.
      final ua = await _evalString(controller, 'navigator.userAgent');
      final cookies = await _cookiesFor(url);
      return ResolvedLink(url, {
        if (ua != null && ua.isNotEmpty) 'User-Agent': ua,
        if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
        'Referer': '${page.scheme}://${page.host}/',
      });
    } finally {
      if (identical(job.value, current)) job.value = null;
      unawaited(
        controller
            .loadRequest(Uri.parse('about:blank'))
            .catchError((Object _) {}),
      );
    }
  }

  static Future<bool> _evalBool(WebViewController c, String js) async {
    try {
      final r = await c.runJavaScriptReturningResult('!!($js)');
      return r == true || r.toString() == 'true' || r.toString() == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _evalString(WebViewController c, String js) async {
    try {
      final r = await c.runJavaScriptReturningResult(js);
      final s = r.toString();
      // Android returns JSON-encoded strings.
      return s.startsWith('"') ? jsonDecode(s) as String : s;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _cookiesFor(String url) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _native.invokeMethod<String>('getCookies', {'url': url});
    } catch (_) {
      return null;
    }
  }
}
