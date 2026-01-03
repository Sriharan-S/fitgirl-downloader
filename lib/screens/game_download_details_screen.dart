import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';

import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:go_router/go_router.dart';

class GameDownloadDetailsScreen extends ConsumerStatefulWidget {
  final String gameTitle;

  const GameDownloadDetailsScreen({super.key, required this.gameTitle});

  @override
  ConsumerState<GameDownloadDetailsScreen> createState() =>
      _GameDownloadDetailsScreenState();
}

class _GameDownloadDetailsScreenState
    extends ConsumerState<GameDownloadDetailsScreen> {
  bool _showAllFiles = false;

  @override
  Widget build(BuildContext context) {
    // 1. Watch the specific session
    final sessions = ref.watch(downloadsProvider);
    final sessionIndex = sessions.indexWhere(
      (s) => s.gameTitle == widget.gameTitle,
    );

    if (sessionIndex == -1) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Session not found',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final session = sessions[sessionIndex];
    final isRunning = session.activeTaskIds.isNotEmpty && !session.isPaused;

    // Calculate Stats
    final completedCount = session.completedUrls.length;
    final totalCount = session.totalFiles;
    double overallProgress = session.overallProgress;

    // ETA Calc (Rough)
    String etaString = '--';
    if (isRunning &&
        session.networkSpeed > 0 &&
        session.totalGameSize != 'TBD') {
      // Try parsing total size
      double totalMB = _parseSizeToMB(session.totalGameSize);
      if (totalMB > 0) {
        double remainingMB = totalMB * (1 - overallProgress);
        double secondsRemaining =
            remainingMB / session.networkSpeed; // MB / MB/s = s
        if (secondsRemaining.isFinite && secondsRemaining > 0) {
          etaString = _formatDuration(
            Duration(seconds: secondsRemaining.toInt()),
          );
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Download Details',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header (Image + Title)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: session.coverUrl,
                    width: 80,
                    height: 110,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.gameTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.hardDrive,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              session.totalGameSize,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 2. Action Buttons
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  await DownloadService().togglePauseSession(session.gameTitle);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning
                      ? Colors.amber
                      : AppTheme.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRunning ? LucideIcons.pause : LucideIcons.play,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRunning ? 'Pause Download' : 'Resume Download',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () async {
                  // 1. Pause if running
                  bool wasRunning =
                      session.activeTaskIds.isNotEmpty && !session.isPaused;
                  if (wasRunning) {
                    await DownloadService().togglePauseSession(
                      session.gameTitle,
                    );
                  }

                  if (!context.mounted) return;

                  // 2. Prepare Data
                  final allFiles = session.originalUrls.isNotEmpty
                      ? session.originalUrls
                      : [...session.pendingUrls, ...session.completedUrls];

                  final currentSelection = [
                    ...session.pendingUrls,
                    ...session.completedUrls,
                  ];

                  // 3. Navigate to Selection
                  final selectedFiles = await context.push<List<String>>(
                    '/select-files',
                    extra: {
                      'game': Game(
                        id: 'dummy', // Required by Game model
                        title: session.gameTitle,
                        coverUrl: session.coverUrl,
                        url: '',
                        size: session.totalGameSize,
                        genre: 'Unknown',
                        version: 'Unknown',
                      ),
                      'fileUrls': allFiles,
                      'initialSelection': currentSelection,
                      'completedFiles': session.completedUrls,
                    },
                  );

                  // 4. Update Session if changed
                  if (selectedFiles != null && context.mounted) {
                    await DownloadService().updateSession(
                      session.gameTitle,
                      selectedFiles,
                    );

                    // 5. Resume if it was running or simply resume to process new queue
                    // It is better UX to auto-resume after "Updating" files.
                    // But we should check if session is currently paused (it IS, because we paused it).
                    // So we implicitly resume.
                    await DownloadService().togglePauseSession(
                      session.gameTitle,
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download queue updated')),
                    );
                  } else {
                    // User cancelled selection, resume if we paused it?
                    if (wasRunning && context.mounted) {
                      await DownloadService().togglePauseSession(
                        session.gameTitle,
                      );
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[800]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.list, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      'Pause and Select Files',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  _showCancelConfirmation(context, session);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.x, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Cancel Download',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 3. Stats Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL PROGRESS',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'ETA: $etaString',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(overallProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Text(
                          _formatProgressSizeString(
                            session.totalGameSize,
                            overallProgress,
                          ),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryGreen,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. Grid Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: LucideIcons.download,
                    label: 'DOWNLOAD',
                    value: '${session.networkSpeed.toStringAsFixed(1)} MB/s',
                    color: AppTheme.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: LucideIcons.upload,
                    label: 'UPLOAD',
                    value: '0 KB/s',
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Row 2 of stats (mocked for visual completeness)
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: LucideIcons.gauge,
                    label: 'AVERAGE',
                    // Use session avgSpeed
                    value: '${session.avgSpeed.toStringAsFixed(1)} MB/s',
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: LucideIcons.zap,
                    label: 'PEAK',
                    // Use session peakSpeed
                    value: '${session.peakSpeed.toStringAsFixed(1)} MB/s',
                    color: Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 5. Currently Downloading
            const Text(
              'Currently Downloading',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          LucideIcons.file,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.currentFileName.isEmpty
                                  ? 'Waiting...'
                                  : session.currentFileName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              session.activeTaskIds.isNotEmpty
                                  ? 'Part ${session.completedUrls.length + 1} of ${session.totalFiles}'
                                  : 'Idle',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(session.currentFileProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: session.currentFileProgress,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryGreen,
                      ),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        session.isPaused ? 'Paused' : 'Downloading...',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                      Text(
                        '-- / --',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 6. Files List (Reordered: Active -> Queued -> Completed)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Files',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${session.completedUrls.length}/${session.totalFiles} Completed',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // List Components
            // 1. Current Active (Usually just 1, handled above but let's show in list too?)
            // User requested "currently downloading and queued should be on top".
            // We already showed "Currently Downloading" as a big card.
            // Should we repeat it in the list? Maybe. Let's do it for completeness if requested.
            if (session.currentFileName.isNotEmpty)
              _buildFileItem(session.currentFileName, false, true),

            // 2. Queued (Pending)
            // Check limit
            Builder(
              builder: (context) {
                final queuedToShow = _showAllFiles
                    ? session.pendingUrls
                    : session.pendingUrls.take(5);
                return Column(
                  children: queuedToShow
                      .map((u) => _buildFileItem(u, false, false))
                      .toList(),
                );
              },
            ),

            // 3. Completed (Bottom)
            Builder(
              builder: (context) {
                final completedToShow = _showAllFiles
                    ? session.completedUrls
                    : session.completedUrls.reversed.take(
                        5,
                      ); // Show latest completed if truncated
                return Column(
                  children: completedToShow
                      .map((u) => _buildFileItem(u, true, false))
                      .toList(),
                );
              },
            ),

            // Show More Button
            if (!_showAllFiles &&
                (session.totalFiles > 10 ||
                    session.pendingUrls.length > 5 ||
                    session.completedUrls.length > 5))
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showAllFiles = true),
                    child: const Text(
                      'Show All Files',
                      style: TextStyle(color: AppTheme.primaryGreen),
                    ),
                  ),
                ),
              ),

            if (_showAllFiles &&
                (session.totalFiles > 10 ||
                    session.pendingUrls.length > 5 ||
                    session.completedUrls.length > 5))
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showAllFiles = false),
                    child: const Text(
                      'Show Less',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(String urlOrName, bool isCompleted, bool isActive) {
    // Robust Filename Logic
    String filename = urlOrName;
    try {
      // If it looks like a URL, try to extract semantic name
      if (urlOrName.startsWith('http') || urlOrName.contains('/')) {
        Uri uri = Uri.parse(urlOrName);
        // 1. Fragment
        if (uri.fragment.isNotEmpty) {
          filename = uri.fragment;
        }
        // 2. Last Segment
        else if (uri.pathSegments.isNotEmpty &&
            uri.pathSegments.last.isNotEmpty) {
          filename = uri.pathSegments.last;
        } else {
          // Fallback to full path if last segment is empty (e.g., ends with /)
          filename = uri.path;
        }
      }
      // Decode URL-encoded characters and replace invalid filename characters
      filename = Uri.decodeFull(
        filename,
      ).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll('_', ' ');

      // Truncate if too long (visual polish)
      if (filename.length > 50)
        filename = '...${filename.substring(filename.length - 47)}';
    } catch (e) {
      filename = urlOrName; // Fallback
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppTheme.primaryGreen.withOpacity(0.2)
              : Colors.white.withOpacity(0.02),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppTheme.primaryGreen
                  : (isActive ? Colors.transparent : Colors.grey[900]),
              shape: BoxShape.circle,
              border: isCompleted
                  ? null
                  : Border.all(
                      color: isActive
                          ? AppTheme.primaryGreen
                          : Colors.grey[700]!,
                    ),
            ),
            child: isCompleted
                ? const Icon(LucideIcons.check, size: 14, color: Colors.black)
                : (isActive
                      ? const Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryGreen,
                          ),
                        )
                      : Icon(
                          LucideIcons.clock,
                          size: 12,
                          color: Colors.grey[700],
                        )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    color: isCompleted || isActive
                        ? Colors.white
                        : Colors.grey[500],
                    fontWeight: isCompleted || isActive
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isCompleted
                      ? 'Done'
                      : (isActive ? 'Downloading...' : 'Queued'),
                  style: TextStyle(
                    color: isCompleted
                        ? Colors.grey[600]
                        : (isActive ? AppTheme.primaryGreen : Colors.grey[800]),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            const Text(
              '', // Size if known
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
        ],
      ),
    );
  }

  void _showCancelConfirmation(
    BuildContext context,
    dynamic
    session, // Passed as dynamic or specific type, here dynamic to avoid import issues if any, but ideally typed
  ) {
    bool deleteFiles = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                'Cancel Download?',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure you want to cancel this download session?',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: deleteFiles,
                        activeColor: Colors.red,
                        checkColor: Colors.white,
                        side: const BorderSide(color: Colors.grey),
                        onChanged: (val) {
                          setDialogState(() {
                            deleteFiles = val ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'Delete downloaded items as well',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('No', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () {
                    // 1. Close dialog
                    Navigator.pop(dialogContext);
                    // 2. Close Details Screen immediately (Back to Downloads)
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    // 3. Perform Cancel in background
                    // We don't await this because we want to leave the screen immediately
                    DownloadService().cancelSession(
                      session.gameTitle,
                      deleteFiles: deleteFiles,
                    );
                  },
                  child: const Text(
                    'Yes, Cancel',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: Colors.grey[400]),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper functions
  String _formatProgressSizeString(String totalSizeStr, double progress) {
    if (totalSizeStr == 'TBD' || totalSizeStr == 'Unknown') {
      return '';
    }

    try {
      double totalMB = _parseSizeToMB(totalSizeStr);
      if (totalMB <= 0) return '';
      double totalGB = totalMB / 1024;

      double downloadedGB = totalGB * progress;

      if (totalGB < 1.0) {
        // Show in MB
        return '${(downloadedGB * 1024).toStringAsFixed(1)} MB / ${(totalGB * 1024).toStringAsFixed(1)} MB';
      }

      return '${downloadedGB.toStringAsFixed(2)} GB / ${totalGB.toStringAsFixed(2)} GB';
    } catch (e) {
      return '';
    }
  }

  double _parseSizeToMB(String sizeStr) {
    try {
      String cleanSize = sizeStr.toUpperCase().replaceAll(',', '.');
      if (cleanSize.contains('GB')) {
        return (double.tryParse(cleanSize.replaceAll('GB', '').trim()) ?? 0.0) *
            1024;
      } else if (cleanSize.contains('MB')) {
        return double.tryParse(cleanSize.replaceAll('MB', '').trim()) ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }
}
