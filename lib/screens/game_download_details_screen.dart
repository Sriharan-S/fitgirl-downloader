import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Full-page version (phones / narrow windows).
class GameDownloadDetailsScreen extends StatelessWidget {
  final String gameTitle;

  const GameDownloadDetailsScreen({super.key, required this.gameTitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download details', style: TextStyle(fontSize: 18)),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/downloads'),
        ),
      ),
      body: DownloadDetailsView(gameTitle: gameTitle),
    );
  }
}

enum _FileFilter { all, active, queued, done, failed }

/// Details of one game download. Used as a page and as the right-hand pane of
/// the desktop Downloads screen.
class DownloadDetailsView extends ConsumerStatefulWidget {
  final String gameTitle;
  final VoidCallback? onRemoved;

  const DownloadDetailsView({
    super.key,
    required this.gameTitle,
    this.onRemoved,
  });

  @override
  ConsumerState<DownloadDetailsView> createState() =>
      _DownloadDetailsViewState();
}

class _DownloadDetailsViewState extends ConsumerState<DownloadDetailsView> {
  _FileFilter _filter = _FileFilter.all;

  @override
  void didUpdateWidget(covariant DownloadDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameTitle != widget.gameTitle) _filter = _FileFilter.all;
  }

  bool _matches(DownloadFile f) {
    switch (_filter) {
      case _FileFilter.all:
        return true;
      case _FileFilter.active:
        return f.status.isActive;
      case _FileFilter.queued:
        return f.status == FileStatus.queued || f.status == FileStatus.paused;
      case _FileFilter.done:
        return f.status == FileStatus.completed;
      case _FileFilter.failed:
        return f.status == FileStatus.failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(downloadSessionProvider(widget.gameTitle));
    if (session == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.packageX, size: 48, color: Colors.white12),
            SizedBox(height: 12),
            Text(
              'This download no longer exists',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    // Active first, then waiting, then failed, then done — keeping order.
    int rank(DownloadFile f) => switch (f.status) {
      FileStatus.downloading || FileStatus.resolving => 0,
      FileStatus.paused || FileStatus.queued => 1,
      FileStatus.failed => 2,
      FileStatus.completed => 3,
    };
    final indexed = session.files.indexed.toList()
      ..sort((a, b) {
        final r = rank(a.$2).compareTo(rank(b.$2));
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    final files = indexed.map((e) => e.$2).where(_matches).toList();
    final pad = context.pagePadding;

    return Scrollbar(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
            sliver: SliverList.list(
              children: [
                _Header(session: session, onRemoved: widget.onRemoved),
                const SizedBox(height: 20),
                _ProgressCard(session: session),
                const SizedBox(height: 12),
                _StatsGrid(session: session),
                const SizedBox(height: 24),
                _filterBar(session),
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (files.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No files in this view',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 40),
              sliver: SliverList.builder(
                itemCount: files.length,
                itemBuilder: (context, i) => _FileRow(
                  key: ValueKey(files[i].url),
                  session: session,
                  file: files[i],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterBar(DownloadSession s) {
    final counts = {
      _FileFilter.all: s.totalFiles,
      _FileFilter.active: s.activeCount,
      _FileFilter.queued: s.queuedCount + s.countWhere(FileStatus.paused),
      _FileFilter.done: s.completedCount,
      _FileFilter.failed: s.failedCount,
    };
    const labels = {
      _FileFilter.all: 'All',
      _FileFilter.active: 'Active',
      _FileFilter.queued: 'Waiting',
      _FileFilter.done: 'Done',
      _FileFilter.failed: 'Failed',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Files',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _FileFilter.values)
              if (f == _FileFilter.all || counts[f]! > 0)
                ChoiceChip(
                  label: Text('${labels[f]} ${counts[f]}'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  showCheckmark: false,
                  selectedColor: AppTheme.primaryGreen,
                  backgroundColor: AppTheme.surfaceDark,
                  side: const BorderSide(color: AppTheme.border),
                  labelStyle: TextStyle(
                    color: _filter == f ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final DownloadSession session;
  final VoidCallback? onRemoved;
  const _Header({required this.session, this.onRemoved});

  @override
  Widget build(BuildContext context) {
    final service = DownloadService();
    final s = session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(url: s.coverUrl, width: 84, height: 116),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    s.gameTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(status: s.status),
                      _Pill(icon: LucideIcons.hardDrive, text: s.totalGameSize),
                      _Pill(
                        icon: LucideIcons.calendar,
                        text: 'Added ${formatRelativeDate(s.createdAt)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Theme(
          data: context.isCompact
              ? _compactButtons(Theme.of(context))
              : Theme.of(context),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!s.isCompleted) PauseResumeButton(session: s),
              OutlinedButton.icon(
                onPressed: () => manageSessionFiles(context, s),
                icon: const Icon(LucideIcons.listChecks, size: 18),
                label: const Text('Add / remove files'),
              ),
              if (s.failedCount > 0)
                OutlinedButton.icon(
                  onPressed: () => service.retryFailed(s.gameTitle),
                  icon: const Icon(LucideIcons.rotateCcw, size: 18),
                  label: Text('Retry ${s.failedCount} failed'),
                ),
              if (service.canOpenFolders)
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await service.openGameFolder(s.gameTitle);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Folder does not exist yet'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.folderOpen, size: 18),
                  label: const Text('Open folder'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: BorderSide(
                    color: AppTheme.danger.withValues(alpha: 0.5),
                  ),
                ),
                onPressed: () => confirmCancelSession(
                  context,
                  s,
                  onCancelled: () {
                    if (onRemoved != null) {
                      onRemoved!();
                    } else if (context.canPop()) {
                      context.pop();
                    }
                  },
                ),
                icon: const Icon(LucideIcons.trash2, size: 18),
                label: Text(s.isCompleted ? 'Remove' : 'Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static ThemeData _compactButtons(ThemeData t) {
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    return t.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: t.filledButtonTheme.style?.copyWith(
          padding: const WidgetStatePropertyAll(pad),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: t.outlinedButtonTheme.style?.copyWith(
          padding: const WidgetStatePropertyAll(pad),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final DownloadSession session;
  const _ProgressCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final pct = s.overallProgress * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${pct.toStringAsFixed(pct >= 100 ? 0 : 1)}%',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        sessionProgressLabel(s),
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (s.status == SessionStatus.downloading)
                        Text(
                          'ETA ${formatDuration(s.eta)}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GreenProgressBar(
              value: s.overallProgress,
              height: 10,
              color: s.isPaused ? AppTheme.warning : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final DownloadSession session;
  const _StatsGrid({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final tiles = [
      _Stat(
        LucideIcons.download,
        'SPEED',
        formatSpeed(s.networkSpeed),
        AppTheme.primaryGreen,
      ),
      _Stat(LucideIcons.gauge, 'AVERAGE', formatSpeed(s.avgSpeed), null),
      _Stat(LucideIcons.zap, 'PEAK', formatSpeed(s.peakSpeed), null),
      _Stat(
        LucideIcons.files,
        'FILES',
        '${s.completedCount} / ${s.totalFiles}',
        null,
      ),
      if (s.isTorrent) ...[
        _Stat(
          LucideIcons.users,
          'PEERS',
          '${s.torrent!.peers} (${s.torrent!.seeders} seeds)',
          null,
        ),
        _Stat(
          LucideIcons.upload,
          'UPLOAD',
          formatSpeed(s.torrent!.uploadRate),
          null,
        ),
      ] else ...[
        _Stat(LucideIcons.activity, 'ACTIVE', '${s.activeCount}', null),
        _Stat(
          LucideIcons.alertTriangle,
          'FAILED',
          '${s.failedCount}',
          s.failedCount > 0 ? AppTheme.danger : null,
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 720 ? 6 : (c.maxWidth >= 330 ? 3 : 2);
        final width = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _Stat(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color ?? Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FileAction { pause, resume, retry, prioritize, remove }

class _FileRow extends StatelessWidget {
  final DownloadSession session;
  final DownloadFile file;
  const _FileRow({super.key, required this.session, required this.file});

  @override
  Widget build(BuildContext context) {
    final f = file;
    final style = fileStatusStyle(f);
    final showBar =
        f.status == FileStatus.downloading ||
        (f.status == FileStatus.paused && f.progress > 0);

    final details = <String>[style.label];
    if (f.status == FileStatus.downloading) {
      if (f.speed > 0) details.add(formatSpeed(f.speed));
      if (f.timeRemaining != null && f.timeRemaining!.inSeconds > 0) {
        details.add(formatDuration(f.timeRemaining));
      }
    }
    if (f.expectedSize > 0) {
      details.add(
        f.status == FileStatus.completed
            ? formatBytes(f.expectedSize)
            : '${formatBytes(f.downloadedBytes)} / ${formatBytes(f.expectedSize)}',
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: f.status.isActive
            ? AppTheme.primaryGreen.withValues(alpha: 0.04)
            : AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: f.status.isActive
              ? AppTheme.primaryGreen.withValues(alpha: 0.25)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          _FileIcon(file: f),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: f.status == FileStatus.completed
                        ? Colors.white60
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  details.join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: style.color, fontSize: 11),
                ),
                if (f.status == FileStatus.failed && f.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      f.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (showBar) ...[
                  const SizedBox(height: 6),
                  GreenProgressBar(
                    value: f.progress,
                    height: 3,
                    color: f.status == FileStatus.paused
                        ? AppTheme.warning
                        : null,
                  ),
                ],
              ],
            ),
          ),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final f = file;
    final service = DownloadService();
    final title = session.gameTitle;

    Widget iconButton(IconData icon, String tip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 16),
          onPressed: onPressed,
        );

    // Torrent files are managed as a whole (pause the game, add/remove
    // files); completed files have nothing left to do.
    if (f.status == FileStatus.completed || session.isTorrent) {
      return const [SizedBox(width: 8)];
    }

    final primary = switch (f.status) {
      FileStatus.downloading || FileStatus.resolving => iconButton(
        LucideIcons.pause,
        'Pause file',
        () => service.pauseFile(title, f.url),
      ),
      FileStatus.paused => iconButton(
        LucideIcons.play,
        'Resume file',
        () => service.resumeFile(title, f.url),
      ),
      FileStatus.failed => iconButton(
        LucideIcons.rotateCcw,
        'Retry',
        () => service.resumeFile(title, f.url),
      ),
      _ => null,
    };

    return [
      ?primary,
      PopupMenuButton<_FileAction>(
        tooltip: 'File actions',
        icon: const Icon(LucideIcons.moreHorizontal, size: 16),
        onSelected: (a) {
          switch (a) {
            case _FileAction.pause:
              service.pauseFile(title, f.url);
            case _FileAction.resume:
            case _FileAction.retry:
              service.resumeFile(title, f.url);
            case _FileAction.prioritize:
              service.prioritizeFile(title, f.url);
            case _FileAction.remove:
              service.removeFile(title, f.url);
          }
        },
        itemBuilder: (_) => [
          if (f.status == FileStatus.queued)
            const PopupMenuItem(value: _FileAction.pause, child: Text('Pause')),
          if (f.status == FileStatus.queued || f.status == FileStatus.paused)
            const PopupMenuItem(
              value: _FileAction.prioritize,
              child: Text('Download next'),
            ),
          const PopupMenuItem(
            value: _FileAction.remove,
            child: Text(
              'Remove from download',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    ];
  }
}

class _FileIcon extends StatelessWidget {
  final DownloadFile file;
  const _FileIcon({required this.file});

  @override
  Widget build(BuildContext context) {
    const size = 26.0;
    switch (file.status) {
      case FileStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: AppTheme.primaryGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.check, size: 14, color: Colors.black),
        );
      case FileStatus.downloading:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: file.progress > 0 ? file.progress : null,
            strokeWidth: 2.5,
            backgroundColor: const Color(0xFF2A2A2A),
          ),
        );
      case FileStatus.resolving:
        return const SizedBox(
          width: size,
          height: size,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.lightBlueAccent,
            ),
          ),
        );
      case FileStatus.paused:
        return const _CircleIcon(LucideIcons.pause, AppTheme.warning);
      case FileStatus.failed:
        return const _CircleIcon(LucideIcons.x, AppTheme.danger);
      case FileStatus.queued:
        return const _CircleIcon(LucideIcons.clock, AppTheme.textMuted);
    }
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _CircleIcon(this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}
