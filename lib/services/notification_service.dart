import 'dart:io';

import 'package:fitgirl_mobile_flutter/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Game-level notifications ("download finished", "file failed") on every
/// platform. Per-file progress notifications on Android/iOS are handled by
/// background_downloader itself (it keeps the download service in the
/// foreground); desktop has no such thing, so these toasts are the only
/// feedback there when the window is in the background.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1000;

  /// Invoked when a notification is clicked.
  VoidCallback? onTap;

  static const _channel = AndroidNotificationDetails(
    'fitgirl_events',
    'Download events',
    channelDescription: 'Finished games and failed downloads',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> initialize() async {
    if (_ready || kIsWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'FitGirl Downloader',
          appUserModelId: 'Sriharan.FitGirlDownloader',
          guid: '3f1c7a52-6b8e-4c1d-9a7e-2d5b8f0e4a11',
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) => onTap?.call(),
      );
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService: init failed: $e');
    }
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      if (Platform.isAndroid) {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
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
  ) => _show('Download failed: $gameTitle', '$file — $error');

  Future<void> _show(String title, String body) async {
    if (!_ready || !SettingsService().value.notificationsEnabled) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: show failed: $e');
    }
  }
}
