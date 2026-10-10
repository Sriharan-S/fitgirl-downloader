import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges a [ValueListenable] into Riverpod state.
class _ListenableNotifier<T> extends Notifier<T> {
  final ValueListenable<T> Function() source;
  _ListenableNotifier(this.source);

  @override
  T build() {
    final listenable = source();
    void listener() => state = listenable.value;
    listenable.addListener(listener);
    ref.onDispose(() => listenable.removeListener(listener));
    return listenable.value;
  }
}

final downloadsProvider =
    NotifierProvider<
      _ListenableNotifier<List<DownloadSession>>,
      List<DownloadSession>
    >(() => _ListenableNotifier(() => DownloadService().sessionsNotifier));

final settingsProvider =
    NotifierProvider<_ListenableNotifier<AppSettings>, AppSettings>(
      () => _ListenableNotifier(() => SettingsService().notifier),
    );

/// A single download by game title (null when it doesn't exist).
final downloadSessionProvider = Provider.family<DownloadSession?, String>((
  ref,
  title,
) {
  final sessions = ref.watch(downloadsProvider);
  for (final s in sessions) {
    if (s.gameTitle == title) return s;
  }
  return null;
});
