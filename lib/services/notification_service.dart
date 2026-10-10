import 'dart:io';

import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Game-level alerts ("download finished", "file failed").
///
/// On Android/iOS, background_downloader already shows a grouped progress /
/// finished / failed notification, so nothing extra is shown there.
///
/// Desktop has no downloader notifications, so alerts are sent through the
/// operating system's own tooling (PowerShell toast on Windows, osascript on
/// macOS, notify-send on Linux). This deliberately avoids a native
/// notification plugin: those must be compiled with the app and have broken
/// the Windows build with newer Visual Studio versions.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Must match the AppUserModelID set on the Start menu shortcut by
  /// windows/installer.iss, so toasts carry the app's name and icon.
  static const windowsAppId = 'Sriharan.FitGirlDownloader';

  /// Fallback for portable/dev runs without an installed shortcut.
  static const _powershellAppId =
      r'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe';

  /// Invoked when a notification is clicked (mobile only).
  VoidCallback? onTap;

  Future<void> initialize() async {}

  Future<void> requestPermission() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      }
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
    }
  }

  Future<void> showGameCompleted(String gameTitle, int fileCount) => _show(
    'Download complete',
    '$gameTitle is ready to install ($fileCount files).',
  );

  Future<void> showDownloadFailed(
    String gameTitle,
    String file,
    String error,
  ) => _show('Download failed: $gameTitle', '$file - $error');

  Future<void> _show(String title, String body) async {
    if (!isDesktopPlatform || !SettingsService().value.notificationsEnabled) {
      return;
    }
    try {
      if (Platform.isWindows) {
        await _showWindows(title, body);
      } else if (Platform.isMacOS) {
        await Process.run('osascript', [
          '-e',
          'display notification "${_escapeAppleScript(body)}" '
              'with title "${_escapeAppleScript(title)}"',
        ]);
      } else if (Platform.isLinux) {
        await Process.run('notify-send', [
          '-a',
          'FitGirl Downloader',
          title,
          body,
        ]);
      }
    } catch (e) {
      debugPrint('NotificationService: show failed: $e');
    }
  }

  Future<void> _showWindows(String title, String body) async {
    final appId = _hasStartMenuShortcut() ? windowsAppId : _powershellAppId;
    // Text is passed through environment variables, never interpolated into
    // the script, so game titles cannot inject PowerShell.
    const script = r'''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$texts = $xml.GetElementsByTagName('text')
$texts.Item(0).AppendChild($xml.CreateTextNode($env:FG_TITLE)) | Out-Null
$texts.Item(1).AppendChild($xml.CreateTextNode($env:FG_BODY)) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($env:FG_APPID).Show($toast)
''';
    await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        script,
      ],
      environment: {'FG_TITLE': title, 'FG_BODY': body, 'FG_APPID': appId},
    );
  }

  bool _hasStartMenuShortcut() {
    const name =
        r'Microsoft\Windows\Start Menu\Programs\FitGirl Downloader.lnk';
    for (final root in [
      Platform.environment['APPDATA'],
      Platform.environment['ProgramData'],
    ]) {
      if (root != null && File('$root\\$name').existsSync()) return true;
    }
    return false;
  }

  static String _escapeAppleScript(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
