import 'dart:async';

import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:fitgirl_mobile_flutter/widgets/featured_carousel.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_vertical.dart';
import 'package:fitgirl_mobile_flutter/widgets/skeleton_game_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  static const _pageSize = 12;
  static const _featuredCount = 5;

  final _scrollController = ScrollController();
  final _popularController = ScrollController();

  final List<Game> _popular = [];
  final List<Game> _newlyAdded = [];
  StreamSubscription<Game>? _popularSub;
  StreamSubscription<Game>? _newSub;

  bool _popularLoading = true;
  bool _newLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refresh();
    // Ask for notification/battery/storage permissions once the UI is up.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) DownloadService().ensureBackgroundPermissions();
    });
  }

  @override
  void dispose() {
    _popularSub?.cancel();
    _newSub?.cancel();
    _scrollController.dispose();
    _popularController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _popularSub?.cancel();
    await _newSub?.cancel();
    setState(() {
      _popular.clear();
      _newlyAdded.clear();
      _popularLoading = true;
      _newLoading = true;
      _hasMore = true;
      _offset = 0;
    });

    final popularDone = Completer<void>();
    _popularSub = ScraperService().streamPopularGames().listen(
      (g) => mounted ? setState(() => _popular.add(g)) : null,
      onDone: () {
        if (mounted) setState(() => _popularLoading = false);
        popularDone.complete();
      },
    );
    await Future.wait([popularDone.future, _loadNewlyAdded(reset: true)]);
  }

  Future<void> _loadNewlyAdded({bool reset = false}) async {
    if (!reset && (_loadingMore || _newLoading || !_hasMore)) return;
    final done = Completer<void>();
    setState(() => _loadingMore = !reset);
    final before = _newlyAdded.length;
    _newSub = ScraperService()
        .streamNewlyAddedGames(offset: _offset, count: _pageSize)
        .listen(
          (g) {
            if (mounted && !_newlyAdded.any((e) => e.url == g.url)) {
              setState(() => _newlyAdded.add(g));
            }
          },
          onDone: () {
            _offset += _pageSize;
            if (mounted) {
              setState(() {
                _newLoading = false;
                _loadingMore = false;
                _hasMore =
                    _newlyAdded.length > before &&
                    ScraperService().hasMoreNewlyAdded(_offset);
              });
            }
            done.complete();
          },
        );
    return done.future;
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 600) _loadNewlyAdded();
  }

  void _scrollShelf(double direction) {
    final target = (_popularController.offset + direction * 600).clamp(
      0.0,
      _popularController.position.maxScrollExtent,
    );
    _popularController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final featured = _popular.take(_featuredCount).toList();
    final shelf = _popular.skip(_featuredCount).toList();
    final active = ref
        .watch(downloadsProvider)
        .where((s) => !s.isCompleted)
        .toList();
    final nothingLoaded =
        !_popularLoading &&
        !_newLoading &&
        _popular.isEmpty &&
        _newlyAdded.isEmpty;
    final shelfCardWidth = wide ? 180.0 : 150.0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryGreen,
          onRefresh: _refresh,
          child: Scrollbar(
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ContentConstraint(
                    child: PageHeader(
                      title: 'Discover',
                      overline: 'FITGIRL REPACKS',
                      actions: [
                        if (isDesktopPlatform)
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: _refresh,
                            icon: const Icon(LucideIcons.refreshCw),
                          ),
                      ],
                    ),
                  ),
                ),
                const SliverContent(
                  extraPadding: EdgeInsets.only(top: 4, bottom: 16),
                  sliver: SliverToBoxAdapter(child: _SearchPill()),
                ),
                if (nothingLoaded)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(onRetry: _refresh),
                  )
                else ...[
                  SliverContent(
                    sliver: SliverToBoxAdapter(
                      child: FeaturedCarousel(
                        games: featured,
                        loading: _popularLoading,
                      ),
                    ),
                  ),
                  if (active.isNotEmpty) ...[
                    _sectionHeader(
                      'Continue downloading',
                      trailing: TextButton(
                        onPressed: () => context.go('/downloads'),
                        child: const Text('See all'),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: ContentConstraint(
                        child: SizedBox(
                          height: 92,
                          child: ListView.separated(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.pagePadding,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: active.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) =>
                                _ActiveDownloadChip(session: active[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (shelf.isNotEmpty || _popularLoading) ...[
                    _sectionHeader(
                      'Popular now',
                      trailing: wide && shelf.length > 4
                          ? Row(
                              children: [
                                IconButton(
                                  tooltip: 'Previous',
                                  onPressed: () => _scrollShelf(-1),
                                  icon: const Icon(LucideIcons.chevronLeft),
                                ),
                                IconButton(
                                  tooltip: 'Next',
                                  onPressed: () => _scrollShelf(1),
                                  icon: const Icon(LucideIcons.chevronRight),
                                ),
                              ],
                            )
                          : null,
                    ),
                    SliverToBoxAdapter(
                      child: ContentConstraint(
                        child: SizedBox(
                          height: shelfCardWidth / GameCardVertical.aspectRatio,
                          child: ListView.separated(
                            controller: _popularController,
                            padding: EdgeInsets.symmetric(
                              horizontal: context.pagePadding,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: shelf.isEmpty ? 5 : shelf.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, i) => SizedBox(
                              width: shelfCardWidth,
                              child: shelf.isEmpty
                                  ? const SkeletonGameCardVertical()
                                  : GameCardVertical(game: shelf[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  _sectionHeader('Newly added'),
                  SliverContent(
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: wide ? 210 : 190,
                        childAspectRatio: GameCardVertical.aspectRatio,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= _newlyAdded.length) {
                            return const SkeletonGameCardVertical();
                          }
                          return GameCardVertical(game: _newlyAdded[index]);
                        },
                        childCount:
                            _newlyAdded.length +
                            (_newLoading || _loadingMore ? 6 : 0),
                      ),
                    ),
                  ),
                  if (_hasMore && !_newLoading && !_loadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadNewlyAdded,
                            icon: const Icon(
                              LucideIcons.chevronsDown,
                              size: 18,
                            ),
                            label: const Text('Load more'),
                          ),
                        ),
                      ),
                    ),
                ],
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: ContentConstraint(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            24,
            context.pagePadding - 8,
            10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable search field that jumps to the Search tab.
class _SearchPill extends StatelessWidget {
  const _SearchPill();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          color: AppTheme.surfaceHighlight,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => context.go('/search'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(LucideIcons.search, size: 20, color: AppTheme.textMuted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Search games',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveDownloadChip extends StatelessWidget {
  final DownloadSession session;
  const _ActiveDownloadChip({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final running = s.status == SessionStatus.downloading;
    final pct = '${(s.overallProgress * 100).toStringAsFixed(0)}%';
    return SizedBox(
      width: 300,
      child: Material(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openDownloadDetails(context, s.gameTitle),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                CoverImage(url: s.coverUrl, width: 52, height: 70, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.gameTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GreenProgressBar(
                        value: s.overallProgress,
                        height: 5,
                        color: s.isPaused ? AppTheme.warning : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        running
                            ? '$pct  ${formatSpeed(s.networkSpeed)}'
                            : '$pct  ${sessionStatusStyle(s.status).label}',
                        style: TextStyle(
                          fontSize: 11,
                          color: running
                              ? AppTheme.primaryGreen
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              "Couldn't reach FitGirl Repacks",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
