import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadsNotifier extends Notifier<List<DownloadSession>> {
  @override
  List<DownloadSession> build() {
    // Listen to the service
    final service = DownloadService();

    // We attach a listener to the service's ValueNotifier
    // When service updates sessions, we update our state
    service.sessionsNotifier.addListener(_onServiceUpdate);

    // Initial State
    return service.sessions;
  }

  void _onServiceUpdate() {
    state = DownloadService().sessionsNotifier.value;
  }
}

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadSession>>(
      DownloadsNotifier.new,
    );
