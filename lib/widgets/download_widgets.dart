import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// =============================================================================
// Status presentation
// =============================================================================

({String label, Color color, IconData icon}) sessionStatusStyle(
  SessionStatus s,
) {
  switch (s) {
    case SessionStatus.downloading:
      return (
        label: 'Downloading',
        color: AppTheme.primaryGreen,
        icon: LucideIcons.arrowDownCircle,
      );
    case SessionStatus.queued:
      return (
        label: 'Queued',
        color: Colors.lightBlueAccent,
        icon: LucideIcons.clock,
      );
    case SessionStatus.paused:
      return (
        label: 'Paused',
        color: AppTheme.warning,
        icon: LucideIcons.pauseCircle,
      );
    case SessionStatus.failed:
      return (
        label: 'Failed',
        color: AppTheme.danger,
        icon: LucideIcons.alertCircle,
      );
    case SessionStatus.completed:
      return (
        label: 'Completed',
        color: AppTheme.primaryGreen,
        icon: LucideIcons.checkCircle,
      );
  }
}

({String label, Color color}) fileStatusStyle(DownloadFile f) {
  switch (f.status) {
    case FileStatus.queued:
      return (label: 'Queued', color: AppTheme.textMuted);
    case FileStatus.resolving:
      return (label: 'Getting link…', color: Colors.lightBlueAccent);
    case FileStatus.downloading:
      return (label: 'Downloading', color: AppTheme.primaryGreen);
    case FileStatus.paused:
      return f.error != null
          ? (
              label: 'Retrying soon (attempt ${f.attempts})',
              color: AppTheme.warning,
            )
          : (label: 'Paused', color: AppTheme.warning);
    case FileStatus.completed:
      return (label: 'Done', color: AppTheme.textMuted);
    case FileStatus.failed:
      return (label: 'Failed', color: AppTheme.danger);
  }
}

class StatusChip extends StatelessWidget {
  final SessionStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final style = sessionStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.color),
          const SizedBox(width: 4),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class GreenProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  const GreenProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color ?? AppTheme.primaryGreen,
      ),
    );
  }
}

class CoverImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double radius;
  const CoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? _placeholder()
          : CachedNetworkImage(
              cacheManager: appImageCache,
              imageUrl: url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              memCacheWidth: (width * 3).round(),
              placeholder: (_, _) => _placeholder(),
              errorWidget: (_, _, _) => _placeholder(),
            ),
    );
  }

  Widget _placeholder() => Container(
    width: width,
    height: height,
    color: AppTheme.surfaceHighlight,
    child: const Icon(LucideIcons.gamepad2, color: Colors.white24),
  );
}

/// "1.2 GB / 35.4 GB" when sizes are known, file count otherwise.
String sessionProgressLabel(DownloadSession s) {
  final total = s.estimatedTotalBytes;
  if (total > 0) {
    return '${formatBytes(s.downloadedBytes)} / ${formatBytes(total)}';
  }
  return '${s.completedCount} / ${s.totalFiles} files';
}

// =============================================================================
// Session card (downloads list)
// =============================================================================

class SessionCard extends StatelessWidget {
  final DownloadSession session;
  final bool selected;
  final VoidCallback onTap;

  const SessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final status = s.status;
    final running = status == SessionStatus.downloading;

    return Material(
      color: selected
          ? AppTheme.primaryGreen.withValues(alpha: 0.07)
          : AppTheme.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: Colors.white.withValues(alpha: 0.03),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryGreen.withValues(alpha: 0.5)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(url: s.coverUrl, width: 64, height: 88),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            s.gameTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (!s.isCompleted)
                          PauseResumeButton(session: s, compact: true),
                        SessionActionsMenu(session: s),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(status: status),
                        if (s.isTorrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'TORRENT • ${s.torrent!.peers} peers',
                              style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Text(
                          '${s.completedCount}/${s.totalFiles} files',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (s.failedCount > 0)
                          Text(
                            '${s.failedCount} failed',
                            style: const TextStyle(
                              color: AppTheme.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GreenProgressBar(
                      value: s.overallProgress,
                      color: status == SessionStatus.paused
                          ? AppTheme.warning
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.isCompleted
                                ? 'Finished ${formatRelativeDate(s.completedAt)}'
                                : sessionProgressLabel(s),
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: running
                                  ? [
                                      TextSpan(
                                        text: formatSpeed(s.networkSpeed),
                                        style: const TextStyle(
                                          color: AppTheme.primaryGreen,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '  ETA ${formatDuration(s.eta)}',
                                      ),
                                    ]
                                  : [
                                      if (!s.isCompleted)
                                        TextSpan(
                                          text:
                                              '${(s.overallProgress * 100).toStringAsFixed(1)}%',
                                        ),
                                    ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PauseResumeButton extends StatelessWidget {
  final DownloadSession session;
  final bool compact;
  const PauseResumeButton({
    super.key,
    required this.session,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final paused = session.isPaused;
    final icon = paused ? LucideIcons.play : LucideIcons.pause;
    final label = paused ? 'Resume' : 'Pause';
    void onPressed() => DownloadService().togglePauseSession(session.gameTitle);

    if (compact) {
      return IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 18,
          color: paused ? AppTheme.primaryGreen : AppTheme.warning,
        ),
        onPressed: onPressed,
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: paused ? AppTheme.primaryGreen : AppTheme.warning,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// =============================================================================
// Actions
// =============================================================================

/// Opens the file picker for an existing download and applies the result
/// without interrupting what is already downloading.
Future<void> manageSessionFiles(
  BuildContext context,
  DownloadSession session,
) async {
  final allFiles = session.originalUrls.isNotEmpty
      ? session.originalUrls
      : session.selectedUrls;
  final selected = await context.push<List<String>>(
    '/select-files',
    extra: {
      'game': Game(
        id: session.gameUrl ?? session.gameTitle,
        title: session.gameTitle,
        coverUrl: session.coverUrl,
        url: session.gameUrl ?? '',
        size: session.totalGameSize,
      ),
      'fileUrls': allFiles,
      'initialSelection': session.selectedUrls,
      'completedFiles': session.completedUrls,
    },
  );
  if (selected == null) return;
  await DownloadService().updateSelection(session.gameTitle, selected);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('File selection updated')));
  }
}

Future<void> confirmCancelSession(
  BuildContext context,
  DownloadSession session, {
  VoidCallback? onCancelled,
}) async {
  bool deleteFiles = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          session.isCompleted ? 'Remove download?' : 'Cancel download?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.isCompleted
                  ? '"${session.gameTitle}" will be removed from the list.'
                  : 'All remaining files of "${session.gameTitle}" will be cancelled.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteFiles,
              activeColor: AppTheme.danger,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => deleteFiles = v ?? false),
              title: const Text(
                'Also delete downloaded files from disk',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Keep',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(session.isCompleted ? 'Remove' : 'Cancel download'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return;
  onCancelled?.call();
  await DownloadService().cancelSession(
    session.gameTitle,
    deleteFiles: deleteFiles,
  );
}

enum _SessionAction {
  manageFiles,
  retryFailed,
  openFolder,
  moveUp,
  moveDown,
  viewGame,
  cancel,
}

class SessionActionsMenu extends StatelessWidget {
  final DownloadSession session;
  final VoidCallback? onRemoved;
  const SessionActionsMenu({super.key, required this.session, this.onRemoved});

  @override
  Widget build(BuildContext context) {
    final service = DownloadService();
    return PopupMenuButton<_SessionAction>(
      tooltip: 'More actions',
      icon: const Icon(LucideIcons.moreVertical, size: 18),
      onSelected: (action) async {
        switch (action) {
          case _SessionAction.manageFiles:
            await manageSessionFiles(context, session);
          case _SessionAction.retryFailed:
            await service.retryFailed(session.gameTitle);
          case _SessionAction.openFolder:
            final ok = await service.openGameFolder(session.gameTitle);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Folder does not exist yet')),
              );
            }
          case _SessionAction.moveUp:
            service.moveSession(session.gameTitle, -1);
          case _SessionAction.moveDown:
            service.moveSession(session.gameTitle, 1);
          case _SessionAction.viewGame:
            if (session.gameUrl != null && session.gameUrl!.isNotEmpty) {
              context.go(
                '/downloads/game?id=${Uri.encodeQueryComponent(session.gameUrl!)}',
              );
            }
          case _SessionAction.cancel:
            if (context.mounted) {
              await confirmCancelSession(
                context,
                session,
                onCancelled: onRemoved,
              );
            }
        }
      },
      itemBuilder: (context) => [
        _item(
          _SessionAction.manageFiles,
          LucideIcons.listChecks,
          'Add / remove files',
        ),
        if (session.failedCount > 0)
          _item(
            _SessionAction.retryFailed,
            LucideIcons.rotateCcw,
            'Retry failed files',
          ),
        if (service.canOpenFolders)
          _item(
            _SessionAction.openFolder,
            LucideIcons.folderOpen,
            'Open folder',
          ),
        if (!session.isCompleted) ...[
          _item(_SessionAction.moveUp, LucideIcons.arrowUp, 'Move up in queue'),
          _item(
            _SessionAction.moveDown,
            LucideIcons.arrowDown,
            'Move down in queue',
          ),
        ],
        if (session.gameUrl != null && session.gameUrl!.isNotEmpty)
          _item(_SessionAction.viewGame, LucideIcons.info, 'View game page'),
        const PopupMenuDivider(),
        _item(
          _SessionAction.cancel,
          LucideIcons.trash2,
          session.isCompleted ? 'Remove from list' : 'Cancel download',
          color: AppTheme.danger,
        ),
      ],
    );
  }

  PopupMenuItem<_SessionAction> _item(
    _SessionAction value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? Colors.white70),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
