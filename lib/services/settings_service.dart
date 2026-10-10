import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  /// Custom download root picked by the user (null = platform default).
  final String? downloadPath;

  /// How many files download at the same time (across all games).
  final int maxConcurrent;

  /// How many times a failed file is retried automatically (with a fresh link).
  final int autoRetries;

  final bool notificationsEnabled;

  /// Download only one game at a time (files of the next game wait).
  final bool oneGameAtATime;

  /// Keep uploading torrents after they finish.
  final bool seedTorrents;

  /// Show adult (NSFW) games on the Discover page. Off by default.
  final bool showNsfw;

  const AppSettings({
    this.downloadPath,
    this.maxConcurrent = 1,
    this.autoRetries = 3,
    this.notificationsEnabled = true,
    this.oneGameAtATime = false,
    this.seedTorrents = false,
    this.showNsfw = false,
  });

  AppSettings copyWith({
    String? downloadPath,
    int? maxConcurrent,
    int? autoRetries,
    bool? notificationsEnabled,
    bool? oneGameAtATime,
    bool? seedTorrents,
    bool? showNsfw,
  }) {
    return AppSettings(
      downloadPath: downloadPath ?? this.downloadPath,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      autoRetries: autoRetries ?? this.autoRetries,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      oneGameAtATime: oneGameAtATime ?? this.oneGameAtATime,
      seedTorrents: seedTorrents ?? this.seedTorrents,
      showNsfw: showNsfw ?? this.showNsfw,
    );
  }
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _kPath = 'custom_download_path'; // Kept from v1 for migration
  // v2: the default changed to sequential (one file at a time).
  static const _kConcurrent = 'max_concurrent_downloads_v2';
  static const _kRetries = 'auto_retries';
  static const _kNotifications = 'notifications_enabled';
  static const _kOneGame = 'one_game_at_a_time';
  static const _kSeed = 'seed_torrents';
  static const _kNsfw = 'show_nsfw';

  final ValueNotifier<AppSettings> notifier = ValueNotifier(
    const AppSettings(),
  );

  AppSettings get value => notifier.value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = AppSettings(
      downloadPath: prefs.getString(_kPath),
      maxConcurrent: prefs.getInt(_kConcurrent) ?? 1,
      autoRetries: prefs.getInt(_kRetries) ?? 3,
      notificationsEnabled: prefs.getBool(_kNotifications) ?? true,
      oneGameAtATime: prefs.getBool(_kOneGame) ?? false,
      seedTorrents: prefs.getBool(_kSeed) ?? false,
      showNsfw: prefs.getBool(_kNsfw) ?? false,
    );
  }

  Future<void> update(AppSettings settings) async {
    notifier.value = settings;
    final prefs = await SharedPreferences.getInstance();
    if (settings.downloadPath != null) {
      await prefs.setString(_kPath, settings.downloadPath!);
    }
    await prefs.setInt(_kConcurrent, settings.maxConcurrent);
    await prefs.setInt(_kRetries, settings.autoRetries);
    await prefs.setBool(_kNotifications, settings.notificationsEnabled);
    await prefs.setBool(_kOneGame, settings.oneGameAtATime);
    await prefs.setBool(_kSeed, settings.seedTorrents);
    await prefs.setBool(_kNsfw, settings.showNsfw);
  }
}
