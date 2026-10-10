import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/screens/game_download_details_screen.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum _Tab { active, completed }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _Tab _tab = _Tab.active;
  String? _selected; // Desktop master/detail selection

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(downloadsProvider);
    final active = sessions.where((s) => !s.isCompleted).toList();
    final completed = sessions.where((s) => s.isCompleted).toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.createdAt).compareTo(
          a.completedAt ?? a.createdAt,
        ),
      );
    final list = _tab == _Tab.active ? active : completed;
    final wide = context.isWide;

    if (wide && list.isNotEmpty && !list.any((s) => s.gameTitle == _selected)) {
      _selected = list.first.gameTitle;
    }

    final header = _buildHeader(active, completed);
    final listView = _buildList(list, wide);

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: context.windowSize == WindowSize.large ? 460 : 400,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        Expanded(child: listView),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selected == null || list.isEmpty
                        ? const _EmptyDetail()
                        : DownloadDetailsView(
                            key: ValueKey(_selected),
                            gameTitle: _selected!,
                            onRemoved: () => setState(() => _selected = null),
                          ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Expanded(child: listView),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(
    List<DownloadSession> active,
    List<DownloadSession> completed,
  ) {
    final service = DownloadService();
    final speed = active.fold<double>(0, (s, e) => s + e.networkSpeed);
    final downloading = active
        .where((s) => s.status == SessionStatus.downloading)
        .length;
    final anyRunning = active.any((s) => !s.isPaused);
    final anyPaused = active.any((s) => s.isPaused);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Downloads',
          overline: active.isEmpty
              ? 'ALL DONE'
              : '$downloading DOWNLOADING · ${formatSpeed(speed).toUpperCase()}',
          actions: [
            if (anyRunning)
              IconButton(
                tooltip: 'Pause all',
                onPressed: service.pauseAll,
                icon: const Icon(LucideIcons.pauseCircle),
              ),
            if (anyPaused)
              IconButton(
                tooltip: 'Resume all',
                onPressed: service.resumeAll,
                icon: const Icon(
                  LucideIcons.playCircle,
                  color: AppTheme.primaryGreen,
                ),
              ),
            IconButton(
              tooltip: 'Download settings',
              onPressed: () => context.go('/settings'),
              icon: const Icon(LucideIcons.settings2),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_Tab>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _Tab.active,
                      label: Text('Active (${active.length})'),
                    ),
                    ButtonSegment(
                      value: _Tab.completed,
                      label: Text('Done (${completed.length})'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() {
                    _tab = s.first;
                    _selected = null;
                  }),
                ),
              ),
              if (_tab == _Tab.completed && completed.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear completed list (files stay on disk)',
                  onPressed: service.clearCompleted,
                  icon: const Icon(LucideIcons.listX),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<DownloadSession> list, bool wide) {
    if (list.isEmpty) {
      return _EmptyList(active: _tab == _Tab.active);
    }
    return Scrollbar(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          context.pagePadding,
          0,
          context.pagePadding,
          24,
        ),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = list[i];
          return SessionCard(
            key: ValueKey(s.gameTitle),
            session: s,
            selected: wide && s.gameTitle == _selected,
            onTap: () {
              if (wide) {
                setState(() => _selected = s.gameTitle);
              } else {
                openDownloadDetails(context, s.gameTitle);
              }
            },
          );
        },
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  final bool active;
  const _EmptyList({required this.active});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? LucideIcons.downloadCloud : LucideIcons.checkCircle,
              size: 52,
              color: Colors.white12,
            ),
            const SizedBox(height: 14),
            Text(
              active ? 'No active downloads' : 'No completed games yet',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
            if (active) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(LucideIcons.compass, size: 18),
                label: const Text('Discover games'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.mousePointerClick, size: 44, color: Colors.white12),
          SizedBox(height: 12),
          Text(
            'Select a download to see its files',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
