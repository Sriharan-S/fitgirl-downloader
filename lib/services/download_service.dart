import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/services/notification_service.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum QueueResult { added, merged }

/// Download engine.
///
/// Every game is a [DownloadSession] holding an ordered list of
/// [DownloadFile]s. A scheduler ([_pump]) starts queued files across all
/// non-paused sessions while respecting the concurrency limit. Mirror links
/// are resolved to direct links right before a file starts (direct links
/// expire), and resumes/retries always fetch a fresh link.
class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  static const _prefsKey = 'download_sessions';
  static const _taskGroup = 'fitgirl';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final ValueNotifier<List<DownloadSession>> sessionsNotifier = ValueNotifier(
    const [],
  );

  /// Invoked when the user taps a download notification.
  VoidCallback? onOpenDownloads;

  List<DownloadSession> _sessions = [];
  final Map<String, (String, String)> _taskIndex = {}; // taskId -> (title, url)
  final Set<String> _retryTimers = {};

  bool _initialized = false;
  bool _pumping = false;
  bool _pumpAgain = false;
  Timer? _emitTimer;
  Timer? _saveTimer;
  Timer? _statsTimer;

  AppSettings get _settings => SettingsService().value;
  List<DownloadSession> get sessions => List.unmodifiable(_sessions);

  // ===========================================================================
  // Setup
  // ===========================================================================

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await SettingsService().load();
    await NotificationService().initialize();

    await FileDownloader().configure(
      globalConfig: [(Config.requestTimeout, const Duration(seconds: 60))],
      androidConfig: [
        (Config.useCacheDir, Config.never),
        (Config.runInForeground, Config.always),
      ],
    );

    // One grouped, progress-bar notification for all running files (mobile).
    FileDownloader().configureNotificationForGroup(
      _taskGroup,
      running: const TaskNotification(
        'Downloading {numFinished}/{numTotal} files',
        '{progress} • {networkSpeed}',
      ),
      complete: const TaskNotification(
        'Downloads finished',
        '{numFinished} files downloaded',
      ),
      error: const TaskNotification(
        'Some downloads failed',
        '{numFailed} failed • open the app to retry',
      ),
      progressBar: true,
      groupNotificationId: 'fitgirl_downloads',
    );

    FileDownloader().registerCallbacks(
      group: _taskGroup,
      taskStatusCallback: _onStatus,
      taskProgressCallback: _onProgress,
      taskNotificationTapCallback: (_, _) => onOpenDownloads?.call(),
    );

    await FileDownloader().trackTasks();
    await _loadSessions();
    await _reconcileWithDownloader();

    // Restores callbacks for tasks that kept running while the app was dead
    // (mobile). Killed tasks are re-queued by _reconcileWithDownloader, so
    // the downloader must not reschedule them on its own.
    await FileDownloader().start(doRescheduleKilledTasks: false);

    SettingsService().notifier.addListener(_pump);
    _pump();
  }

  // ===========================================================================
  // Public API: queueing & selection
  // ===========================================================================

  /// Adds a game to the queue. If it is already queued the new files are
  /// merged into the existing download instead of being ignored.
  Future<QueueResult> queueGame({
    required String gameTitle,
    required String coverUrl,
    required List<String> urls,
    required String totalGameSize,
    String? gameUrl,
    List<String> allUrls = const [],
  }) async {
    final existing = _indexOf(gameTitle);
    if (existing != -1) {
      final session = _sessions[existing];
      await updateSelection(
        gameTitle,
        {...session.selectedUrls, ...urls}.toList(),
      );
      if (session.isPaused) await resumeSession(gameTitle);
      return QueueResult.merged;
    }

    _sessions.add(
      DownloadSession.create(
        gameTitle: gameTitle,
        coverUrl: coverUrl,
        gameUrl: gameUrl,
        urls: urls,
        totalGameSize: totalGameSize,
        originalUrls: allUrls,
      ),
    );
    _changed(saveNow: true);
    _pump();
    return QueueResult.added;
  }

  /// Applies a new file selection to a running/paused/completed download.
  /// New files are queued immediately, deselected files are cancelled.
  /// Completed files are always kept. No pause is required.
  Future<void> updateSelection(String gameTitle, List<String> urls) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final session = _sessions[i];
    final wanted = urls.toSet();

    final kept = <DownloadFile>[];
    for (final f in session.files) {
      if (wanted.contains(f.url) || f.status == FileStatus.completed) {
        kept.add(f);
      } else {
        await _cancelTask(f.taskId);
      }
    }
    final present = kept.map((f) => f.url).toSet();
    final order = {
      for (var j = 0; j < session.originalUrls.length; j++)
        session.originalUrls[j]: j,
    };
    final added = urls.where((u) => !present.contains(u)).toList()
      ..sort((a, b) => (order[a] ?? 1 << 30).compareTo(order[b] ?? 1 << 30));

    final originals = [...session.originalUrls];
    for (final u in added) {
      if (!originals.contains(u)) originals.add(u);
    }

    _sessions[i] = session.copyWith(
      files: [...kept, ...added.map(DownloadFile.fromUrl)],
      originalUrls: originals,
      clearCompletedAt: added.isNotEmpty,
    );
    _changed(saveNow: true);
    _pump();
  }

  // ===========================================================================
  // Public API: session controls
  // ===========================================================================

  Future<void> togglePauseSession(String gameTitle) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    if (_sessions[i].isPaused) {
      await resumeSession(gameTitle);
    } else {
      await pauseSession(gameTitle);
    }
  }

  Future<void> pauseSession(String gameTitle) async {
    final i = _indexOf(gameTitle);
    if (i == -1 || _sessions[i].isPaused) return;
    _sessions[i] = _sessions[i].copyWith(isPaused: true);
    _changed();
    for (final f in _sessions[i].files.where((f) => f.status.isActive)) {
      await _pauseFileInternal(gameTitle, f.url);
    }
    _changed(saveNow: true);
    _pump(); // Free slots go to the next game
  }

  Future<void> resumeSession(String gameTitle) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final s = _sessions[i];
    _sessions[i] = s.copyWith(
      isPaused: false,
      files: [
        for (final f in s.files)
          f.status == FileStatus.paused
              ? f.copyWith(status: FileStatus.queued, speed: 0)
              : f,
      ],
    );
    _changed(saveNow: true);
    _pump();
  }

  Future<void> pauseAll() async {
    for (final s in [..._sessions]) {
      if (!s.isCompleted) await pauseSession(s.gameTitle);
    }
  }

  Future<void> resumeAll() async {
    for (final s in [..._sessions]) {
      if (s.isPaused) await resumeSession(s.gameTitle);
    }
  }

  /// Re-queues every failed file of a game (resets the retry counter).
  Future<void> retryFailed(String gameTitle) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final s = _sessions[i];
    _sessions[i] = s.copyWith(
      isPaused: false,
      files: [
        for (final f in s.files)
          f.status == FileStatus.failed
              ? f.copyWith(
                  status: FileStatus.queued,
                  attempts: 0,
                  clearError: true,
                )
              : f,
      ],
    );
    _changed(saveNow: true);
    _pump();
  }

  /// Cancels a game download and removes it from the list.
  Future<void> cancelSession(
    String gameTitle, {
    bool deleteFiles = false,
  }) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final session = _sessions.removeAt(i);
    _changed(saveNow: true);

    for (final f in session.files) {
      await _cancelTask(f.taskId);
    }
    if (deleteFiles) {
      try {
        final dir = Directory(await gameDirectory(gameTitle));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        debugPrint(
          'DownloadService: failed to delete files for $gameTitle: $e',
        );
      }
    }
    _pump();
  }

  /// Removes finished games from the list (files on disk are kept).
  void clearCompleted() {
    _sessions.removeWhere((s) => s.isCompleted);
    _changed(saveNow: true);
  }

  /// Moves a game up (-1) or down (+1) in the queue; earlier games get
  /// download slots first.
  void moveSession(String gameTitle, int delta) {
    final i = _indexOf(gameTitle);
    final j = i + delta;
    if (i == -1 || j < 0 || j >= _sessions.length) return;
    final s = _sessions.removeAt(i);
    _sessions.insert(j, s);
    _changed(saveNow: true);
    _pump();
  }

  // ===========================================================================
  // Public API: per-file controls
  // ===========================================================================

  Future<void> pauseFile(String gameTitle, String url) async {
    await _pauseFileInternal(gameTitle, url);
    _changed(saveNow: true);
    _pump();
  }

  void resumeFile(String gameTitle, String url) {
    _updateFile(gameTitle, url, (f) {
      if (f.status != FileStatus.paused && f.status != FileStatus.failed) {
        return f;
      }
      return f.copyWith(
        status: FileStatus.queued,
        clearError: true,
        attempts: f.status == FileStatus.failed ? 0 : f.attempts,
      );
    });
    final i = _indexOf(gameTitle);
    if (i != -1 && _sessions[i].isPaused) {
      _sessions[i] = _sessions[i].copyWith(isPaused: false);
    }
    _changed(saveNow: true);
    _pump();
  }

  /// Moves a file to the front of its game's queue.
  void prioritizeFile(String gameTitle, String url) {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final files = [..._sessions[i].files];
    final idx = files.indexWhere((f) => f.url == url);
    if (idx <= 0) return;
    final file = files.removeAt(idx);
    final firstWaiting = files.indexWhere(
      (f) => f.status == FileStatus.queued || f.status == FileStatus.paused,
    );
    files.insert(firstWaiting == -1 ? files.length : firstWaiting, file);
    _sessions[i] = _sessions[i].copyWith(files: files);
    _changed(saveNow: true);
    _pump();
  }

  Future<void> removeFile(String gameTitle, String url) async {
    final i = _indexOf(gameTitle);
    if (i == -1) return;
    final file = _sessions[i].files.firstWhere(
      (f) => f.url == url,
      orElse: () => DownloadFile.fromUrl(url),
    );
    await _cancelTask(file.taskId);
    _sessions[i] = _sessions[i].copyWith(
      files: _sessions[i].files.where((f) => f.url != url).toList(),
    );
    if (_sessions[i].files.isEmpty) _sessions.removeAt(i);
    _changed(saveNow: true);
    _pump();
  }

  // ===========================================================================
  // Public API: storage
  // ===========================================================================

  Future<String?> get downloadDirectory async => _settings.downloadPath;

  /// Root folder that contains `FitGirl_Games/<game>` folders.
  Future<String> downloadRoot() async {
    final custom = _settings.downloadPath;
    if (custom != null && custom.isNotEmpty) return custom;
    try {
      if (isDesktopPlatform) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads.path;
      }
      return (await getApplicationDocumentsDirectory()).path;
    } catch (e) {
      debugPrint('DownloadService: no default download folder: $e');
      return Directory.current.path;
    }
  }

  Future<String> gameDirectory(String gameTitle) async =>
      p.join(await downloadRoot(), 'FitGirl_Games', _safeFolderName(gameTitle));

  /// Lets the user pick the download root. Returns true when changed.
  Future<bool> setDownloadDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select download folder for FitGirl repacks',
    );
    if (path == null) return false;
    await SettingsService().update(_settings.copyWith(downloadPath: path));
    return true;
  }

  /// Whether the user must pick a folder before downloading. Desktop has a
  /// sensible default (the Downloads folder); Android's default app folder
  /// is not reachable by the user, so we ask.
  bool get needsDownloadDirectory =>
      !isDesktopPlatform && (_settings.downloadPath?.isEmpty ?? true);

  Future<bool> openGameFolder(String gameTitle) async {
    final dir = await gameDirectory(gameTitle);
    if (!await Directory(dir).exists()) return false;
    if (isDesktopPlatform) {
      return launchUrl(Uri.directory(dir));
    }
    return false;
  }

  bool get canOpenFolders => isDesktopPlatform;

  // ===========================================================================
  // Permissions (Android)
  // ===========================================================================

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    var status = await Permission.storage.status;
    if (!status.isGranted) status = await Permission.storage.request();
    return status.isGranted;
  }

  Future<void> ensureBackgroundPermissions() async {
    await NotificationService().requestPermission();
    if (!Platform.isAndroid) return;
    if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await requestStoragePermission();
  }

  // ===========================================================================
  // Scheduler
  // ===========================================================================

  void _pump() {
    if (!_initialized) return;
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        int slots =
            _settings.maxConcurrent -
            _sessions.fold<int>(0, (n, s) => n + s.activeCount);
        if (slots <= 0) break;

        for (final session in [..._sessions]) {
          if (slots <= 0) break;
          if (session.isPaused || session.isCompleted) continue;
          final waiting = session.files
              .where((f) => f.status == FileStatus.queued)
              .toList();
          for (final f in waiting) {
            if (slots <= 0) break;
            _startFile(session.gameTitle, f.url);
            slots--;
          }
          // Strict mode: later games wait until this one has nothing left.
          if (_settings.oneGameAtATime &&
              (session.activeCount > 0 ||
                  session.files.any((f) => f.status == FileStatus.queued))) {
            break;
          }
        }
      } while (_pumpAgain);
    } finally {
      _pumping = false;
    }
    _ensureStatsTimer();
  }

  /// Resolves a fresh direct link and starts (or resumes) the file.
  /// Marks the file as resolving synchronously so [_pump] counts the slot.
  Future<void> _startFile(String title, String url) async {
    final file = _updateFile(
      title,
      url,
      (f) => f.copyWith(status: FileStatus.resolving, clearError: true),
    );
    if (file == null) return;
    _changed();

    String? direct;
    String? error;
    try {
      direct = await _resolveDirectLink(url);
    } catch (e) {
      error = 'Could not get download link: $e';
    }

    // The user may have paused/removed the file while we were resolving.
    final current = _findFile(title, url);
    final session = _sessions.elementAtOrNull(_indexOf(title));
    if (current == null || session == null) return;
    if (current.status != FileStatus.resolving || session.isPaused) {
      if (current.status == FileStatus.resolving) {
        _updateFile(title, url, (f) => f.copyWith(status: FileStatus.paused));
        _changed();
      }
      return;
    }

    if (direct == null) {
      _handleFailure(
        title,
        url,
        error ?? 'Mirror did not return a download link',
      );
      return;
    }

    // Re-checked after every await: the user may pause or remove the file
    // at any time. State is committed before each downloader call so a
    // concurrent pause always finds the task it has to stop.
    bool stillWanted() {
      final f = _findFile(title, url);
      final i = _indexOf(title);
      return f != null &&
          i != -1 &&
          !_sessions[i].isPaused &&
          f.status != FileStatus.paused;
    }

    try {
      // 1) Resume from partial data when we have it (pause, crash, failure).
      if (current.taskId != null) {
        final stored = await _storedTask(current.taskId!);
        if (!stillWanted()) return;
        if (stored != null) {
          _taskIndex[stored.taskId] = (title, url);
          _updateFile(
            title,
            url,
            (f) => f.copyWith(status: FileStatus.downloading),
          );
          _changed();
          if (await FileDownloader().resume(stored.copyWith(url: direct))) {
            _changed(saveNow: true);
            return;
          }
          if (!stillWanted()) return;
        }
        _taskIndex.remove(current.taskId);
      }

      // 2) Fresh download.
      final task = await _buildTask(title, url, direct);
      if (!stillWanted()) return;
      _taskIndex[task.taskId] = (title, url);
      _updateFile(
        title,
        url,
        (f) => f.copyWith(
          status: FileStatus.downloading,
          taskId: task.taskId,
          progress: 0,
        ),
      );
      _changed(saveNow: true);
      final ok = await FileDownloader().enqueue(task);
      if (!ok) {
        _taskIndex.remove(task.taskId);
        _handleFailure(title, url, 'Downloader rejected the task');
      }
    } catch (e) {
      _handleFailure(title, url, 'Failed to start: $e');
    }
  }

  Future<String?> _resolveDirectLink(String url) async {
    if (!(url.contains('fuckingfast.co') || url.contains('datanodes.to'))) {
      return url; // Already direct
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final link = await ScraperService()
          .getDirectDownloadLink(url)
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (link != null) return link;
      await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<DownloadTask> _buildTask(
    String title,
    String url,
    String direct,
  ) async {
    String fileName = fileNameFromUrl(url);
    if (fileName.length < 5 || !fileName.contains('.')) {
      fileName = fileNameFromUrl(direct);
    }
    fileName = sanitizeFileName(fileName);

    final (baseDirectory, directory) = await _taskLocation(title);
    return DownloadTask(
      url: direct,
      filename: fileName,
      directory: directory,
      baseDirectory: baseDirectory,
      group: _taskGroup,
      headers: const {'User-Agent': _userAgent},
      updates: Updates.statusAndProgress,
      retries: 2,
      allowPause: true,
      metaData: jsonEncode({'title': title, 'url': url}),
      displayName: fileName,
    );
  }

  Future<(BaseDirectory, String)> _taskLocation(String title) async {
    final folder = p.join('FitGirl_Games', _safeFolderName(title));
    final custom = _settings.downloadPath;
    if (custom != null && custom.isNotEmpty) {
      return (BaseDirectory.root, p.join(custom, folder));
    }
    if (isDesktopPlatform) {
      return (BaseDirectory.root, p.join(await downloadRoot(), folder));
    }
    return (BaseDirectory.applicationDocuments, folder);
  }

  Future<DownloadTask?> _storedTask(String taskId) async {
    final record = await FileDownloader().database.recordForId(taskId);
    final task = record?.task;
    return task is DownloadTask ? task : null;
  }

  Future<void> _pauseFileInternal(String title, String url) async {
    final f = _findFile(title, url);
    if (f == null) return;
    if (f.status == FileStatus.queued || f.status == FileStatus.resolving) {
      _updateFile(
        title,
        url,
        (f) => f.copyWith(status: FileStatus.paused, speed: 0),
      );
      return;
    }
    if (f.status != FileStatus.downloading || f.taskId == null) return;

    final task = await FileDownloader().taskForId(f.taskId!);
    bool paused = false;
    if (task is DownloadTask) {
      paused = await FileDownloader().pause(task);
    }
    if (!paused) {
      // Not pausable (server without range support or task not started yet):
      // stop it and restart from scratch on resume.
      await _cancelTask(f.taskId);
      _updateFile(
        title,
        url,
        (f) => f.copyWith(
          status: FileStatus.paused,
          clearTaskId: true,
          progress: 0,
          speed: 0,
        ),
      );
      return;
    }
    _updateFile(
      title,
      url,
      (f) => f.copyWith(
        status: FileStatus.paused,
        speed: 0,
        clearTimeRemaining: true,
      ),
    );
  }

  Future<void> _cancelTask(String? taskId) async {
    if (taskId == null) return;
    _taskIndex.remove(taskId); // Ignore the resulting "canceled" update
    try {
      await FileDownloader().cancelTaskWithId(taskId);
    } catch (_) {}
  }

  void _handleFailure(String title, String url, String error) {
    final f = _findFile(title, url);
    if (f == null) return;
    final attempts = f.attempts + 1;
    final retry = attempts <= _settings.autoRetries;

    _updateFile(
      title,
      url,
      (f) => f.copyWith(
        status: retry ? FileStatus.paused : FileStatus.failed,
        error: error,
        attempts: attempts,
        speed: 0,
        clearTimeRemaining: true,
      ),
    );
    _changed(saveNow: true);

    if (retry) {
      // Back off, then re-queue with a fresh link (resumes if possible).
      final key = '$title|$url';
      if (_retryTimers.add(key)) {
        Timer(Duration(seconds: 5 * attempts), () {
          _retryTimers.remove(key);
          final cur = _findFile(title, url);
          if (cur != null &&
              cur.status == FileStatus.paused &&
              cur.error != null) {
            _updateFile(
              title,
              url,
              (f) => f.copyWith(status: FileStatus.queued),
            );
            _changed();
            _pump();
          }
        });
      }
    } else {
      NotificationService().showDownloadFailed(title, f.name, error);
    }
    _pump();
  }

  // ===========================================================================
  // Downloader callbacks
  // ===========================================================================

  void _onStatus(TaskStatusUpdate update) {
    final ref = _taskIndex[update.task.taskId] ?? _refFromMeta(update.task);
    if (ref == null) return;
    final (title, url) = ref;
    final f = _findFile(title, url);
    if (f == null || f.taskId != update.task.taskId) return;

    switch (update.status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
        if (f.status != FileStatus.paused) {
          _updateFile(
            title,
            url,
            (f) => f.copyWith(status: FileStatus.downloading),
          );
        }
        break;
      case TaskStatus.paused:
        _updateFile(
          title,
          url,
          (f) => f.copyWith(status: FileStatus.paused, speed: 0),
        );
        break;
      case TaskStatus.waitingToRetry:
        _updateFile(title, url, (f) => f.copyWith(speed: 0));
        break;
      case TaskStatus.complete:
        _taskIndex.remove(update.task.taskId);
        _updateFile(
          title,
          url,
          (f) => f.copyWith(
            status: FileStatus.completed,
            progress: 1,
            speed: 0,
            clearError: true,
            clearTimeRemaining: true,
          ),
        );
        _checkSessionCompleted(title);
        _changed(saveNow: true);
        _pump();
        return;
      case TaskStatus.canceled:
        // Cancelled outside our control (e.g. from the system notification).
        _taskIndex.remove(update.task.taskId);
        _updateFile(
          title,
          url,
          (f) => f.copyWith(
            status: FileStatus.paused,
            clearTaskId: true,
            progress: 0,
            speed: 0,
          ),
        );
        _changed(saveNow: true);
        _pump();
        return;
      case TaskStatus.failed:
      case TaskStatus.notFound:
        final code = update.responseStatusCode;
        final reason =
            update.exception?.description ??
            (code != null ? 'HTTP $code' : update.status.name);
        _taskIndex.remove(update.task.taskId);

        // User paused a file on a server without range support: the
        // downloader reports this as a failure. Keep it paused; it will
        // restart from scratch on resume.
        final userPaused = f.status == FileStatus.paused && f.error == null;
        // A resume with a refreshed link can be rejected (ETag changed or
        // range not honoured): drop the partial data and start over.
        final cannotResume =
            update.exception is TaskResumeException ||
            reason.contains('Cannot resume') ||
            code == 416;

        if (userPaused || cannotResume) {
          _updateFile(
            title,
            url,
            (f) => f.copyWith(
              status: userPaused ? FileStatus.paused : FileStatus.queued,
              clearTaskId: true,
              progress: 0,
              speed: 0,
            ),
          );
          _changed(saveNow: true);
          _pump();
          return;
        }
        // Keep the task id so a retry can resume from the partial file.
        _handleFailure(title, url, reason);
        return;
    }
    _changed();
  }

  void _onProgress(TaskProgressUpdate update) {
    if (update.progress < 0) return; // Negative values encode status changes
    final ref = _taskIndex[update.task.taskId] ?? _refFromMeta(update.task);
    if (ref == null) return;
    final (title, url) = ref;
    _updateFile(title, url, (f) {
      if (f.taskId != update.task.taskId) return f;
      return f.copyWith(
        progress: update.progress,
        expectedSize: update.hasExpectedFileSize
            ? update.expectedFileSize
            : null,
        speed: update.hasNetworkSpeed ? update.networkSpeed : null,
        timeRemaining: update.hasTimeRemaining ? update.timeRemaining : null,
      );
    });
    _changed(throttled: true);
  }

  (String, String)? _refFromMeta(Task task) {
    try {
      final meta = jsonDecode(task.metaData) as Map<String, dynamic>;
      final ref = (meta['title'] as String, meta['url'] as String);
      _taskIndex[task.taskId] = ref;
      return ref;
    } catch (_) {
      return null;
    }
  }

  void _checkSessionCompleted(String title) {
    final i = _indexOf(title);
    if (i == -1) return;
    final s = _sessions[i];
    if (s.isCompleted && s.completedAt == null) {
      _sessions[i] = s.copyWith(completedAt: DateTime.now());
      NotificationService().showGameCompleted(title, s.totalFiles);
    }
  }

  // ===========================================================================
  // Stats (average / peak speed)
  // ===========================================================================

  void _ensureStatsTimer() {
    final anyActive = _sessions.any((s) => s.activeCount > 0);
    if (anyActive && _statsTimer == null) {
      _statsTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickStats(),
      );
    } else if (!anyActive) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  void _tickStats() {
    bool any = false;
    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.status != SessionStatus.downloading) continue;
      any = true;
      final speed = s.networkSpeed;
      if (speed <= 0) continue;
      final avg = s.avgSpeed <= 0 ? speed : s.avgSpeed * 0.9 + speed * 0.1;
      _sessions[i] = s.copyWith(
        avgSpeed: avg,
        peakSpeed: speed > s.peakSpeed ? speed : s.peakSpeed,
      );
    }
    if (!any) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
    _changed(throttled: true);
  }

  // ===========================================================================
  // State helpers
  // ===========================================================================

  int _indexOf(String title) =>
      _sessions.indexWhere((s) => s.gameTitle == title);

  DownloadFile? _findFile(String title, String url) {
    final i = _indexOf(title);
    if (i == -1) return null;
    for (final f in _sessions[i].files) {
      if (f.url == url) return f;
    }
    return null;
  }

  DownloadFile? _updateFile(
    String title,
    String url,
    DownloadFile Function(DownloadFile) fn,
  ) {
    final i = _indexOf(title);
    if (i == -1) return null;
    final files = _sessions[i].files;
    final j = files.indexWhere((f) => f.url == url);
    if (j == -1) return null;
    final updated = fn(files[j]);
    if (identical(updated, files[j])) return updated;
    final copy = [...files];
    copy[j] = updated;
    _sessions[i] = _sessions[i].copyWith(files: copy);
    return updated;
  }

  /// Publishes state to the UI. Progress updates are throttled so dozens of
  /// parallel files don't rebuild the UI hundreds of times per second.
  void _changed({bool throttled = false, bool saveNow = false}) {
    if (throttled) {
      _emitTimer ??= Timer(const Duration(milliseconds: 250), _emit);
      _saveTimer ??= Timer(const Duration(seconds: 5), _flushSave);
    } else {
      _emitTimer?.cancel();
      _emit();
      if (saveNow) {
        _flushSave();
      } else {
        _saveTimer ??= Timer(const Duration(seconds: 2), _flushSave);
      }
    }
  }

  void _emit() {
    _emitTimer = null;
    sessionsNotifier.value = List.unmodifiable(_sessions);
  }

  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveSessions();
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _sessions = list
          .map((e) => DownloadSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('DownloadService: could not load sessions: $e');
    }
  }

  /// Brings persisted file states in line with what the downloader actually
  /// knows after an app restart (tasks may have finished, been killed, ...).
  Future<void> _reconcileWithDownloader() async {
    final db = FileDownloader().database;
    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      final files = <DownloadFile>[];
      for (final f in s.files) {
        if (f.status == FileStatus.completed || f.status == FileStatus.failed) {
          files.add(f.copyWith(speed: 0));
          continue;
        }
        if (f.taskId == null) {
          // Was resolving (no task yet) or queued.
          files.add(
            f.copyWith(
              status: f.status == FileStatus.paused
                  ? FileStatus.paused
                  : FileStatus.queued,
              speed: 0,
            ),
          );
          continue;
        }
        _taskIndex[f.taskId!] = (s.gameTitle, f.url);
        final record = await db.recordForId(f.taskId!);
        final live = await FileDownloader().taskForId(f.taskId!);
        final status = record?.status;
        if (status == TaskStatus.complete) {
          files.add(
            f.copyWith(status: FileStatus.completed, progress: 1, speed: 0),
          );
        } else if (live != null &&
            (status == TaskStatus.running ||
                status == TaskStatus.enqueued ||
                status == TaskStatus.waitingToRetry)) {
          files.add(
            f.copyWith(
              status: FileStatus.downloading,
              progress: record?.progress ?? f.progress,
            ),
          );
        } else if (status == TaskStatus.paused ||
            f.status == FileStatus.paused) {
          files.add(
            f.copyWith(
              status: s.isPaused ? FileStatus.paused : FileStatus.queued,
              speed: 0,
            ),
          );
        } else {
          // Killed with the app (desktop) or lost: start again, but keep the
          // task id so partial data is resumed when the downloader has it.
          files.add(f.copyWith(status: FileStatus.queued, speed: 0));
        }
      }
      _sessions[i] = s.copyWith(files: files);
      if (_sessions[i].isCompleted && _sessions[i].completedAt == null) {
        _sessions[i] = _sessions[i].copyWith(completedAt: DateTime.now());
      }
    }
    _changed(saveNow: true);
  }

  // Same folder naming as v1 so existing partial downloads are found again.
  String _safeFolderName(String title) {
    final safe = title.replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_').trim();
    return safe.length > 100 ? safe.substring(0, 100) : safe;
  }
}
