import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:fitgirl_mobile_flutter/core/app_version.dart';
import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset(this.name, this.url, this.size);
}

class AppRelease {
  final String tag;
  final List<int> version;
  final String notes;
  final String pageUrl;
  final DateTime? publishedAt;
  final ReleaseAsset? asset; // Installer for this platform, if any

  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.publishedAt,
    this.asset,
  });
}

class UpdateCheck {
  final String currentTag;
  final AppRelease latest;

  /// How many releases are newer than the installed one.
  final int versionsBehind;

  const UpdateCheck({
    required this.currentTag,
    required this.latest,
    required this.versionsBehind,
  });

  bool get forced => versionsBehind >= UpdateService.forceAfter;
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// Checks GitHub releases for a newer build and installs it in-app.
///
/// Prompt rules (startup):
/// - at most once per day;
/// - "Later" hides the prompt until tomorrow;
/// - "Skip" hides it until a newer release than the skipped one appears;
/// - [forceAfter] or more releases behind: a forced prompt on every start.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const repo = 'Sriharan-S/fitgirl-downloader';
  static const forceAfter = 3;

  static const _kSkipped = 'update_skipped_tag';
  static const _kRemindAfter = 'update_remind_after';
  static const _kLastPrompt = 'update_last_prompt_day';

  WebClient _web = WebClient(maxConcurrent: 1);
  String _currentTag = AppVersion.current;
  DateTime Function() _now = DateTime.now;

  @visibleForTesting
  void configureForTest({
    WebClient? client,
    String? currentTag,
    DateTime Function()? now,
  }) {
    if (client != null) _web = client;
    if (currentTag != null) _currentTag = currentTag;
    if (now != null) _now = now;
  }

  /// Newest release and how far behind this build is, or null when up to
  /// date, offline, or running a local (non-release) build.
  Future<UpdateCheck?> check() async {
    final current = AppVersion.parse(_currentTag);
    if (current == null) return null;

    final res = await _web.get(
      Uri.parse('https://api.github.com/repos/$repo/releases?per_page=30'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (res.statusCode != 200) {
      throw UpdateException('GitHub returned HTTP ${res.statusCode}');
    }

    final newer = <AppRelease>[];
    for (final r in jsonDecode(res.body) as List<dynamic>) {
      if (r is! Map || r['draft'] == true || r['prerelease'] == true) continue;
      final tag = r['tag_name'] as String? ?? '';
      final version = AppVersion.parse(tag);
      if (version == null || AppVersion.compare(version, current) <= 0) {
        continue;
      }
      newer.add(
        AppRelease(
          tag: tag,
          version: version,
          notes: (r['body'] as String? ?? '').trim(),
          pageUrl: r['html_url'] as String? ?? '',
          publishedAt: DateTime.tryParse(r['published_at'] as String? ?? ''),
          asset: _assetForPlatform(r['assets'] as List<dynamic>? ?? const []),
        ),
      );
    }
    if (newer.isEmpty) return null;
    newer.sort((a, b) => AppVersion.compare(b.version, a.version));
    return UpdateCheck(
      currentTag: _currentTag,
      latest: newer.first,
      versionsBehind: newer.length,
    );
  }

  /// [check] filtered by the prompt rules; null means "don't prompt now".
  Future<UpdateCheck?> checkForStartupPrompt() async {
    final result = await check();
    if (result == null) return null;
    if (result.forced) return result;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kSkipped) == result.latest.tag) return null;

    final now = _now();
    final remindAfter = DateTime.tryParse(prefs.getString(_kRemindAfter) ?? '');
    if (remindAfter != null && now.isBefore(remindAfter)) return null;

    final today = _day(now);
    if (prefs.getString(_kLastPrompt) == today) return null;
    await prefs.setString(_kLastPrompt, today);
    return result;
  }

  /// "Later": ask again tomorrow.
  Future<void> remindLater() async {
    final now = _now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRemindAfter, tomorrow.toIso8601String());
  }

  /// "Skip": don't ask about [tag] again (a newer release asks again).
  Future<void> skip(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkipped, tag);
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Download & install
  // ---------------------------------------------------------------------------

  static String? get _assetSuffix {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '-windows-setup.exe';
    if (Platform.isMacOS) return '-macos-universal.zip';
    if (Platform.isLinux) return '-linux-x64.tar.gz';
    return null; // iOS: unsigned builds can't be installed by the app
  }

  static ReleaseAsset? _assetForPlatform(List<dynamic> assets) {
    final suffix = _assetSuffix;
    if (suffix == null) return null;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = a['name'] as String? ?? '';
      if (name.toLowerCase().endsWith(suffix)) {
        return ReleaseAsset(
          name,
          a['browser_download_url'] as String,
          (a['size'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return null;
  }

  /// Whether this platform installs the update by itself (otherwise the
  /// downloaded file is shown so the user can install it).
  static bool get installsAutomatically =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  /// Downloads the release's installer and starts it. On Windows the app
  /// exits so the installer can replace it (it relaunches the app).
  Future<void> downloadAndInstall(
    AppRelease release, {
    required void Function(double progress) onProgress,
  }) async {
    final asset = release.asset;
    if (asset == null) {
      await launchUrl(
        Uri.parse(release.pageUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final task = DownloadTask(
      url: asset.url,
      filename: asset.name,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: 'updates',
      group: 'app_update',
      updates: Updates.statusAndProgress,
      retries: 2,
    );
    final result = await FileDownloader().download(
      task,
      onProgress: (p) {
        if (p >= 0) onProgress(p);
      },
    );
    if (result.status != TaskStatus.complete) {
      throw UpdateException(
        'Download failed: ${result.exception?.description ?? result.status.name}',
      );
    }
    await _install(await task.filePath());
  }

  Future<void> _install(String path) async {
    if (Platform.isAndroid) {
      if (!await Permission.requestInstallPackages.isGranted &&
          !await Permission.requestInstallPackages.request().isGranted) {
        throw const UpdateException(
          'Allow "Install unknown apps" for FitGirl Downloader, then tap Update again',
        );
      }
      final opened = await FileDownloader().openFile(
        filePath: path,
        mimeType: 'application/vnd.android.package-archive',
      );
      if (!opened) throw const UpdateException('Could not open the installer');
    } else if (Platform.isWindows) {
      await Process.start(path, [
        '/SILENT',
        '/SP-',
        '/NOCANCEL',
        '/SUPPRESSMSGBOXES',
        '/CLOSEAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      exit(0);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]); // Reveal in Finder
    } else if (Platform.isLinux) {
      await launchUrl(Uri.directory(p.dirname(path)));
    }
  }
}
