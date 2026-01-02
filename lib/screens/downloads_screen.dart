import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/widgets/header_icon_button.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/screens/game_download_details_screen.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Watch the provider which is List<DownloadSession>
    final sessions = ref.watch(downloadsProvider);

    final activeSessions = sessions.where((s) => !s.isCompleted).toList();
    final completedSessions = sessions.where((s) => s.isCompleted).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Downloads',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  HeaderIconButton(
                    icon: LucideIcons.folderCog,
                    onTap: () async {
                      await DownloadService().setDownloadDirectory();
                    },
                  ),
                ],
              ),
            ),

            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildTab(0, 'Active', count: activeSessions.length),
                  const SizedBox(width: 12),
                  _buildTab(1, 'Completed', count: completedSessions.length),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // content
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildActiveList(activeSessions)
                  : _buildCompletedList(completedSessions),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveList(List<DownloadSession> sessions) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text(
          'No active downloads',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return GameDownloadCard(session: sessions[index]);
      },
    );
  }

  Widget _buildCompletedList(List<DownloadSession> sessions) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text('No completed games', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return Card(
          color: AppTheme.surfaceDark,
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: session.coverUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
              ),
            ),
            title: Text(
              session.gameTitle,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${session.totalFiles} files downloaded',
              style: const TextStyle(color: Colors.green),
            ),
            trailing: const Icon(LucideIcons.checkCircle, color: Colors.green),
          ),
        );
      },
    );
  }

  Widget _buildTab(int index, String label, {int count = 0}) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.grey[400],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : AppTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? AppTheme.primaryGreen : Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GameDownloadCard extends StatelessWidget {
  final DownloadSession session;

  const GameDownloadCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // Calculated Values
    final completedCount = session.completedUrls.length;
    final totalCount = session.totalFiles;
    // Approximated "Total" progress based on completed files + current file progress
    // Note: This is an approximation since file sizes vary.
    double overallProgress = 0.0;
    if (totalCount > 0) {
      overallProgress =
          (completedCount + session.currentFileProgress) / totalCount;
    }
    if (overallProgress > 1.0) overallProgress = 1.0;

    final hasActiveTasks = session.activeTaskIds.isNotEmpty;
    final isRunning = hasActiveTasks && !session.isPaused;

    // Status text
    String statusText = 'Queued';
    Color statusColor = Colors.grey;

    if (session.isPaused) {
      statusText = 'Paused';
      statusColor = Colors.amber;
    } else if (isRunning) {
      statusText = 'Downloading...';
      statusColor = AppTheme.primaryGreen;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                GameDownloadDetailsScreen(gameTitle: session.gameTitle),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), // Darker card background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with Pulse
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: session.coverUrl,
                    width: 80,
                    height: 120, // Taller aspect ratio
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.grey[800]),
                  ),
                ),
                // Play/Pause Overlay
                GestureDetector(
                  onTap: () async {
                    await DownloadService().togglePauseSession(
                      session.gameTitle,
                    );
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRunning ? LucideIcons.pause : LucideIcons.play,
                      color: AppTheme.primaryGreen,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),

            // Right Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Speed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          session.gameTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isRunning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${session.networkSpeed.toStringAsFixed(1)} MB/s',
                            style: const TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // File Count
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.file,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'File $completedCount/$totalCount',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Total Progress Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Progress',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Text(
                        _formatProgressString(
                          session.totalGameSize,
                          overallProgress,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryGreen,
                      ),
                      minHeight: 6,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Current File Section
                  if (session.activeTaskIds.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            session.currentFileName,
                            style: const TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(session.currentFileProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: session.currentFileProgress,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryGreen,
                        ),
                        minHeight: 3, // Thinner
                      ),
                    ),
                  ] else if (session.isCompleted) ...[
                    const Text(
                      'Installation ready',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatProgressString(String totalSizeStr, double progress) {
    if (totalSizeStr == 'TBD' || totalSizeStr == 'Unknown') {
      return '${(progress * 100).toStringAsFixed(1)}%';
    }

    try {
      // Parse total size
      double totalGB = 0.0;
      // Sanitize string (remove non-breaking spaces if any, verify standard format)
      String cleanSize = totalSizeStr.toUpperCase().replaceAll(',', '.');

      if (cleanSize.contains('GB')) {
        totalGB = double.tryParse(cleanSize.replaceAll('GB', '').trim()) ?? 0.0;
      } else if (cleanSize.contains('MB')) {
        totalGB =
            (double.tryParse(cleanSize.replaceAll('MB', '').trim()) ?? 0.0) /
            1024;
      }

      if (totalGB <= 0.0) return '${(progress * 100).toStringAsFixed(1)}%';

      // Calculate downloaded
      double downloadedGB = totalGB * progress;

      // Handle small sizes (MB vs GB display)
      if (totalGB < 1.0) {
        // Show in MB
        return '${(downloadedGB * 1024).toStringAsFixed(1)} MB / ${(totalGB * 1024).toStringAsFixed(1)} MB';
      }

      return '${downloadedGB.toStringAsFixed(2)} GB / ${totalGB.toStringAsFixed(2)} GB';
    } catch (e) {
      return '${(progress * 100).toStringAsFixed(1)}%';
    }
  }
}
