import 'dart:async';

import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_horizontal.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_vertical.dart';
import 'package:fitgirl_mobile_flutter/widgets/skeleton_game_cards.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _pageSize = 12;

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

  void _scrollPopular(double direction) {
    final target = (_popularController.offset + direction * 640).clamp(
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
    final cardWidth = wide ? 340.0 : 300.0;
    final carouselHeight = wide ? 220.0 : 196.0;
    final nothingLoaded =
        !_popularLoading &&
        !_newLoading &&
        _popular.isEmpty &&
        _newlyAdded.isEmpty;

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
                        IconButton(
                          tooltip: 'Search (Ctrl+F)',
                          onPressed: () => context.go('/search'),
                          icon: const Icon(LucideIcons.search),
                        ),
                      ],
                    ),
                  ),
                ),

                if (nothingLoaded)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(onRetry: _refresh),
                  )
                else ...[
                  _sectionHeader(
                    'Popular Now',
                    trailing: wide && _popular.length > 2
                        ? Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous',
                                onPressed: () => _scrollPopular(-1),
                                icon: const Icon(LucideIcons.chevronLeft),
                              ),
                              IconButton(
                                tooltip: 'Next',
                                onPressed: () => _scrollPopular(1),
                                icon: const Icon(LucideIcons.chevronRight),
                              ),
                            ],
                          )
                        : null,
                  ),
                  SliverToBoxAdapter(
                    child: ContentConstraint(
                      child: SizedBox(
                        height: carouselHeight,
                        child: ListView.separated(
                          controller: _popularController,
                          padding: EdgeInsets.symmetric(
                            horizontal: context.pagePadding,
                            vertical: 6,
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: _popular.isEmpty && _popularLoading
                              ? 4
                              : _popular.length + (_popularLoading ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            if (index >= _popular.length) {
                              return const SkeletonGameCardHorizontal();
                            }
                            return GameCardHorizontal(
                              game: _popular[index],
                              width: cardWidth,
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  _sectionHeader('Newly Added'),
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
            20,
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
