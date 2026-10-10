package com.sriharan.fitgirldownloader

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The torrent engine ships as lib/<abi>/libtorrentd.so (an executable);
        // Dart needs the folder Android extracted it to.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitgirl/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    // Cookies the WebView got from a file host (e.g. Cloudflare
                    // clearance), sent along with the download request.
                    "getCookies" -> result.success(
                        CookieManager.getInstance().getCookie(call.argument<String>("url"))
                    )
                    // Live download notifications (and keeping the app alive).
                    "updateDownloadNotifications" -> {
                        val raw = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        DownloadProgressService.update(applicationContext, raw.map {
                            DownloadProgressService.Item(
                                (it["id"] as Number).toInt(),
                                it["title"] as String,
                                it["text"] as String,
                                (it["progress"] as Number).toInt(),
                            )
                        })
                        result.success(null)
                    }
                    // "Exit" while downloads run: leave the app, keep it alive.
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }
}
