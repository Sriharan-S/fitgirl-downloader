import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:file_picker/file_picker.dart';

import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();

  factory DownloadService() {
    return _instance;
  }

  DownloadService._internal();

  String? _downloadDirectory;
  bool _initialized = false;

  // State
  List<DownloadSession> _sessions = [];
  bool _isProcessing = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Configure FileDownloader
    await FileDownloader().configure(
      globalConfig: [(Config.requestTimeout, const Duration(seconds: 100))],
    );

    // Register generic callback for all tasks to handle queue processing
    FileDownloader().registerCallbacks(
      taskStatusCallback: _onTaskStatusUpdate,
      taskProgressCallback: (update) {
        _onProgressUpdate(update);
        // We'll update providers via a separate stream/listener if needed,
        // but for now the provider polls/listeners to the database.
        // Actually, for our session model, we might need to emit updates.
        // But let's stick to the architecture: Service manages logic, Provider listens to Service/DB.
      },
      taskNotificationTapCallback: (task, notificationType) {
        print('Tapped notification $notificationType');
      },
    );

    // Restore saved download path
    final prefs = await SharedPreferences.getInstance();
    _downloadDirectory = prefs.getString('custom_download_path');

    // Load Sessions
    await _loadSessions();

    // Resume processing if needed
    _processQueue(); // Fire and forget

    _initialized = true;
  }

  // Public Getters for Provider
  List<DownloadSession> get sessions => List.unmodifiable(_sessions);

  // Queue a new game
  Future<void> queueGame({
    required String gameTitle,
    required String coverUrl,
    required List<String> urls,
    required String totalGameSize,
    List<String> allUrls = const [], // Added: Full list of candidate files
  }) async {
    // Check if game already exists?
    // Ideally we merge, but for now simple add
    final session = DownloadSession.create(
      gameTitle: gameTitle,
      coverUrl: coverUrl,
      urls: urls, // These are the initial PENDING urls (selected)
      totalGameSize: totalGameSize,
      originalUrls: allUrls.isNotEmpty
          ? allUrls
          : urls, // Persist all candidates
    );

    _sessions.add(session);
    await _saveSessions();
    _processQueue();
  }

  // Update session with new file selection (Pause/Select feature)
  Future<void> updateSession(
    String gameTitle,
    List<String> newSelectedUrls,
  ) async {
    print(
      'DownloadService: Updating session $gameTitle with ${newSelectedUrls.length} files',
    );

    int index = _sessions.indexWhere((s) => s.gameTitle == gameTitle);
    if (index == -1) return;

    var session = _sessions[index];

    // 1. Identification
    // Current State
    final Set<String> newSelection = newSelectedUrls.toSet();
    final Set<String> completed = session.completedUrls.toSet();

    // 2. Diffing - Active Tasks
    // We need to know which active tasks correspond to which URL to decide if we cancel them.
    // Metadata format: '$gameTitle|$coverUrl|$originalUrl'
    List<String> activeToKeep = [];

    for (var taskId in session.activeTaskIds) {
      final task = await FileDownloader().taskForId(taskId);
      if (task != null) {
        final parts = task.metaData.split('|');
        if (parts.length > 2) {
          final originalUrl = parts[2];
          if (newSelection.contains(originalUrl)) {
            activeToKeep.add(taskId); // Keep it
          } else {
            // Cancel it
            print(
              'Cancelling task $taskId ($originalUrl) as it was deselected.',
            );
            await FileDownloader().cancelTaskWithId(taskId);
          }
        } else {
          // Task has bad metadata? Keep it to be safe, or cancel?
          // Better to keep loop integrity.
          activeToKeep.add(taskId);
        }
      } else {
        // Task not found in downloader but was in session?
        // It's a zombie. Remove it.
      }
    }

    // 3. Diffing - Pending
    // New Pending = New Selection - Completed - Active(Kept)
    // We cannot easily map Active IDs back to URLs without the async lookup above.
    // So let's gather the URLs of the active tasks we KEPT.
    List<String> activeUrls = [];
    for (var taskId in activeToKeep) {
      final task = await FileDownloader().taskForId(taskId);
      if (task != null) {
        final parts = task.metaData.split('|');
        if (parts.length > 2) activeUrls.add(parts[2]);
      }
    }

    List<String> newPending = [];
    for (var url in newSelectedUrls) {
      if (!completed.contains(url) && !activeUrls.contains(url)) {
        newPending.add(url);
      }
    }

    // 4. Update Session
    // We update 'pendingUrls' and 'activeTaskIds'.
    // We also make sure the session is unpaused if we want to resume immediately?
    // User flow: Pause -> Select -> Resume.
    // The "Update" happens when they click "Confirm" in selection.
    // We should probably leave the pause state as is, and let user click "Resume".
    // BUT if we modified the queue, we want to ensure _processQueue picks it up IF not paused.

    _sessions[index] = session.copyWith(
      activeTaskIds: activeToKeep,
      pendingUrls: newPending,
      // Recalculate total files? No, totalFiles should be 'originalUrls.length' or 'newSelectedUrls.length'?
      // Usually 'totalFiles' is the count of *selected* files.
      // So yes, update totalFiles.
      // totalFiles = newSelectedUrls.length?
      // Let's check session definition. "totalFiles" usually tracks "how many files are in this download job".
      // If I unselect files, totalFiles should decrease.
      // If I select new files, totalFiles should increase.
      // So yes, totalFiles = newSelectedUrls.length.
      // Wait, `copywith` doesn't have totalFiles usually?
      // Check model definition... `totalFiles` is final field but NOT in copyWith signature usually?
      // Let's check the model I just updated.
      // Step 2840: `copyWith` DOES NOT have `totalFiles`.
      // `totalFiles` is defined as `final int totalFiles;`.
      // The `copyWith` implementation in Step 2840:
      // `totalFiles: totalFiles,` (it uses `this.totalFiles`).
      // It does NOT allow updating totalFiles.
      // THIS IS A BUG/LIMITATION in my previous model update!
      // I need `totalFiles` to be updateable if the user changes the selection size.

      // I'll assume for now I cannot update `totalFiles` via copyWith.
      // I should fix the model OR (hack) create a new session replacing the old one, but keeping the ID/Speed/etc.
      // Creating a new session is cleaner but we lose transient props if not careful.

      // OPTION: Fix Model first? Or just ignore totalFiles mismatch (progress bar will be wrong).
      // I MUST fix the model to allow `totalFiles` update in `copyWith`.
      // I will add `totalFiles` to `copyWith` in this same step if I can?
      // No, I should stick to Service update here.
      // I will do a separate Tool Call to fix Model `copyWith` first?
      // Actually, I can utilize `replace_file_content` to fix `DownloadSession` now quickly?
      // No, I'm already editing Service. I cannot edit Model in parallel.

      // Strategy: I will finish editing Service, but leave a TODO or workaround.
      // Actually, I can use `_sessions[index] = DownloadSession(...)` constructor directly instead of copyWith to set totalFiles!
      // Yes! `copyWith` is just a helper. I can use the constructor to clone-and-modify manually.
    );

    // Manual clone to update totalFiles
    final updatedSession = _sessions[index].copyWith(
      activeTaskIds: activeToKeep,
      pendingUrls: newPending,
    );
    // Since copyWith doesn't support totalFiles, I have to interpret "totalFiles" as dynamic?
    // No, it's a field.
    // I will reconstruct the session entirely.
    _sessions[index] = DownloadSession(
      gameTitle: updatedSession.gameTitle,
      coverUrl: updatedSession.coverUrl,
      pendingUrls: updatedSession.pendingUrls,
      completedUrls: updatedSession.completedUrls,
      activeTaskIds: updatedSession.activeTaskIds,
      fileProgress: updatedSession.fileProgress,
      networkSpeed: updatedSession.networkSpeed,
      avgSpeed: updatedSession.avgSpeed,
      peakSpeed: updatedSession.peakSpeed,
      currentFileName: updatedSession.currentFileName,
      currentFileProgress: updatedSession.currentFileProgress,
      isPaused: updatedSession.isPaused,
      totalGameSize: updatedSession.totalGameSize,
      originalUrls: updatedSession.originalUrls,
      totalFiles: newSelectedUrls.length, // Update this!
    );

    await _saveSessions();
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Find a session that needs work
      for (int i = 0; i < _sessions.length; i++) {
        var session = _sessions[i];

        // If it has active tasks, we let them run.
        // Assuming we want 1 global concurrent download or 1 per game?
        // User asked for "Sequential". Let's do 1 Global active download for stability.
        // If any session has an active task, we stop.
        if (session.activeTaskIds.isNotEmpty) {
          if (session.isPaused)
            continue; // Skip paused sessions (allows other games to run)
          _isProcessing = false;
          return; // Global busy
        }

        // If paused, don't pick up new work
        if (session.isPaused) continue;

        // If no active tasks, check for pending
        if (session.pendingUrls.isNotEmpty) {
          // Pop the first pending URL
          final urlToProcess = session.pendingUrls.first;
          final remainingUrls = session.pendingUrls.sublist(1);

          // Update session state locally (move to active... sort of, we need a task ID first)
          // Actually, we don't have a task ID yet.

          // Resolve Link (The "Scraper Worker" part)
          String? directLink;
          try {
            if (urlToProcess.contains('fuckingfast.co') ||
                urlToProcess.contains('datanodes.to')) {
              directLink = await ScraperService().getDirectDownloadLink(
                urlToProcess,
              );
            } else {
              directLink = urlToProcess;
            }
          } catch (e) {
            print('Error resolving link $urlToProcess: $e');
            // On error, maybe move to "failed"? For now, just skip/drop to avoid sticking
            // Or better, re-queue at end? Let's treat as "completed" but failed for queue purposes.
            _sessions[i] = session.copyWith(
              pendingUrls: remainingUrls,
              completedUrls: [
                ...session.completedUrls,
                urlToProcess,
              ], // Mark processed
            );
            await _saveSessions();
            _isProcessing = false;
            _processQueue(); // Recurse/Loop
            return;
          }

          if (directLink != null) {
            // Enqueue the download
            await _enqueueActualDownload(
              sessionIndex: i,
              originalUrl: urlToProcess,
              directLink: directLink,
              gameTitle: session.gameTitle,
              coverUrl: session.coverUrl,
            );
            // Update session: removed from pending, added to active (in enqueue helper)
          } else {
            // Failed to resolve
            _sessions[i] = session.copyWith(
              pendingUrls: remainingUrls,
              completedUrls: [...session.completedUrls, urlToProcess],
            );
            await _saveSessions();
          }

          // We started a task, so stop processing loop
          _isProcessing = false;
          return;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _enqueueActualDownload({
    required int sessionIndex,
    required String originalUrl,
    required String directLink,
    required String gameTitle,
    required String coverUrl,
  }) async {
    final session = _sessions[sessionIndex];

    // Logic to determine a clean filename
    // 1. Try to get it from the Original URL fragment (e.g. #File.rar)
    String fileName = Uri.parse(originalUrl).fragment;
    if (fileName.isEmpty) {
      // 2. Try decode from original path end
      fileName = Uri.decodeFull(originalUrl.split('/').last);
    }
    // 3. If original is obscure, fallback to direct link
    if (fileName.isEmpty || fileName.length < 5 || !fileName.contains('.')) {
      fileName = Uri.decodeFull(directLink.split('/').last);
    }
    // 4. Sanitize
    fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    // Directory Logic
    String? baseDir = await downloadDirectory;
    final safeTitle = gameTitle
        .replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_')
        .trim();
    String finalDirectory = 'FitGirl_Games/$safeTitle';
    if (baseDir != null) {
      finalDirectory = '$baseDir/$finalDirectory';
    }

    final task = DownloadTask(
      url: directLink,
      filename: fileName,
      directory: finalDirectory,
      baseDirectory: baseDir != null
          ? BaseDirectory.root
          : BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      metaData:
          '$gameTitle|$coverUrl|$originalUrl', // Store original URL in metadata to map back
      displayName: fileName,
    );

    // Update session state BEFORE enqueue to ensure consistency
    _sessions[sessionIndex] = session.copyWith(
      pendingUrls: session.pendingUrls.sublist(1), // Remove current
      activeTaskIds: [...session.activeTaskIds, task.taskId], // Add new task ID
    );
    await _saveSessions();

    await FileDownloader().enqueue(task);
  }

  void _onTaskStatusUpdate(TaskStatusUpdate update) {
    // Check if any session owns this task
    for (int i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      if (session.activeTaskIds.contains(update.task.taskId)) {
        // Handle completion
        if (update.status == TaskStatus.complete) {
          final newActive = List<String>.from(session.activeTaskIds)
            ..remove(update.task.taskId);

          final parts = update.task.metaData.split('|');
          final originalUrl = parts.length > 2 ? parts[2] : "";

          final newCompleted = List<String>.from(session.completedUrls);
          if (originalUrl.isNotEmpty && !newCompleted.contains(originalUrl)) {
            newCompleted.add(originalUrl);
          }

          _sessions[i] = session.copyWith(
            activeTaskIds: newActive,
            completedUrls: newCompleted,
            currentFileName: '', // Reset on complete
            currentFileProgress: 0.0,
            networkSpeed: 0.0,
          );
          _saveSessions();
          _processQueue();
        }
        // Handle Failure/Cancellation
        else if (update.status == TaskStatus.canceled ||
            update.status == TaskStatus.failed) {
          // ... similar logic, remove from active ...
          final newActive = List<String>.from(session.activeTaskIds)
            ..remove(update.task.taskId);

          // For now, we don't retry failed automatically in this block,
          // _processQueue logic handles retrying unresolved links, but here task failed.
          // Let's just remove it so queue can proceed (or stop).
          _sessions[i] = session.copyWith(
            activeTaskIds: newActive,
            currentFileName: 'Failed',
            networkSpeed: 0.0,
          );
          _saveSessions();
          _processQueue();
        }
        break;
      }
    }
    notifyListeners();
  }

  void _onProgressUpdate(TaskProgressUpdate update) {
    for (int i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      if (session.activeTaskIds.contains(update.task.taskId)) {
        // Check if session is paused but task is still reporting progress
        if (session.isPaused) {
          print(
            'WARNING: Progress received for PAUSED session ${session.gameTitle}. Force cancelling task ${update.task.taskId}...',
          );
          FileDownloader().cancelTaskWithId(update.task.taskId);
          return;
        }

        // Calculate speed
        double currentSpeed = update.networkSpeed > 0
            ? update.networkSpeed
            : 0.0;

        // Update Peak Speed
        double newPeak = currentSpeed > session.peakSpeed
            ? currentSpeed
            : session.peakSpeed;

        // Update Average Speed (Exponential Moving Average for stability)
        // Alpha of 0.05 gives significant smoothing windows
        double newAvg;
        if (session.avgSpeed <= 0) {
          newAvg = currentSpeed;
        } else {
          newAvg = (session.avgSpeed * 0.95) + (currentSpeed * 0.05);
        }

        // Update session
        _sessions[i] = session.copyWith(
          currentFileName: update.task.filename,
          currentFileProgress: update.progress,
          networkSpeed: currentSpeed,
          peakSpeed: newPeak,
          avgSpeed: newAvg,
        );

        notifyListeners();
        break;
      }
    }
  }

  // Persistence
  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(
      _sessions.map((s) => s.toJson()).toList(),
    );
    await prefs.setString('download_sessions', jsonStr);
    notifyListeners(); // We need a way to notify provider? Or provider polls? service shouldn't notify.
    // Ideally use a ValueNotifier or StreamController exposed by Service.
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('download_sessions');
    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _sessions = jsonList.map((e) => DownloadSession.fromJson(e)).toList();
      } catch (e) {
        print('Error loading sessions: $e');
      }
    }
  }

  // Stream for updates (Simple Broadcast)
  // Or just let Provider poll? polling is bad.
  // extending ChangeNotifier logic since we are refactoring.
  // Actually, let's add a ValueNotifier
  final ValueNotifier<List<DownloadSession>> sessionsNotifier = ValueNotifier(
    [],
  );

  // Helper to update notifier whenever sessions change
  void notifyListeners() {
    sessionsNotifier.value = List.from(_sessions);
  }

  // Pass-throughs
  Future<String?> get downloadDirectory async {
    if (_downloadDirectory != null) return _downloadDirectory;
    final prefs = await SharedPreferences.getInstance();
    _downloadDirectory = prefs.getString('custom_download_path');
    return _downloadDirectory;
  }

  // ... keep path setters ...

  Future<bool> setDownloadDirectory() async {
    /* ... same as before ... */
    // Pick folder
    String? path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Download Folder for FitGirl Repacks',
    );

    if (path != null) {
      _downloadDirectory = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_download_path', path);
      return true;
    }
    return false;
  }

  // ... keep permission request ...
  Future<bool> requestStoragePermission() async {
    /* ... same as before ... */
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      if (await Permission.manageExternalStorage.request().isGranted)
        return true;
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  // Keep these for UI controls (Pause/Resume/Cancel Session)
  Future<void> togglePauseSession(String gameTitle) async {
    print('DownloadService: togglePauseSession for $gameTitle');
    for (int i = 0; i < _sessions.length; i++) {
      if (_sessions[i].gameTitle == gameTitle) {
        final session = _sessions[i];
        final newIsPaused = !session.isPaused;

        // 1. Optimistic State Update (Immediate UI response & Block queue)
        _sessions[i] = session.copyWith(
          isPaused: newIsPaused,
          // If pausing, we might want to visually zero speed immediately
          networkSpeed: newIsPaused ? 0.0 : session.networkSpeed,
        );
        notifyListeners(); // Immediate Update
        await _saveSessions();

        // 2. Perform Async Actions
        if (newIsPaused) {
          // PAUSE
          print('DownloadService: Pausing session $gameTitle');
          for (var taskId in session.activeTaskIds) {
            final task = await FileDownloader().taskForId(taskId);
            if (task != null && task is DownloadTask) {
              await FileDownloader().pause(task);
            }
          }
        } else {
          // RESUME
          print('DownloadService: Resuming session $gameTitle');
          for (var taskId in session.activeTaskIds) {
            final task = await FileDownloader().taskForId(taskId);
            if (task != null && task is DownloadTask) {
              await FileDownloader().resume(task);
            }
          }

          // If we have no active tasks to resume (maybe they finished or cancelled?), this will just fall through.
          // _processQueue will pick up the next file if needed.
          _processQueue();
        }
        break;
      }
    }
  }

  // Simplified pause
  Future<void> pauseTask(String taskId) async {
    await FileDownloader().pause(
      await FileDownloader().taskForId(taskId) as DownloadTask,
    );
  }

  Future<void> resumeTask(String taskId) async {
    await FileDownloader().resume(
      await FileDownloader().taskForId(taskId) as DownloadTask,
    );
  }

  Future<void> cancel(String taskId) =>
      FileDownloader().cancelTaskWithId(taskId);
}
