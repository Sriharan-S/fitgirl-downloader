import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_horizontal.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_vertical.dart';
import 'package:fitgirl_mobile_flutter/widgets/header_icon_button.dart';
import 'package:fitgirl_mobile_flutter/widgets/skeleton_game_cards.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Game> _popularGames = [];
  List<Game> _newlyAddedGames = [];
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _popularGames = [];
      _newlyAddedGames = [];
    });

    final scraper = ScraperService();

    // Stream popular games
    scraper.streamPopularGames().listen(
      (game) {
        if (mounted) {
          setState(() {
            _popularGames.add(game);
          });
        }
      },
      onError: (e) {
        print('Error streaming popular game: $e');
      },
    );

    // Stream newly added games
    scraper.streamNewlyAddedGames().listen(
      (game) {
        if (mounted) {
          setState(() {
            _newlyAddedGames.add(game);
          });
        }
      },
      onError: (e) {
        print('Error streaming newly added game: $e');
      },
    );

    // We don't strictly need to await anything here since streams are active
    // But we might want to toggle _isLoading off after some time or when first item arrives?
    // For now, let's just turn _isLoading off immediately or after a short delay
    // to allow the Skeleton loader to be replaced by the empty list (which fills up).
    // Actually, a better UX is: separate loading states or just show list + skeletons.
    // Let's set _isLoading to false effectively immediately, or handle "empty" state better.
    // Simpler approach: _isLoading toggles off when we start listening, relying on
    // empty lists + list builder to show content as it arrives.
    // BUT, if we set _isLoading = false immediately, the "No popular games found" text might flash.
    // So let's add a small flag or just keep _isLoading true until at least one item arrives?
    // No, let's keep _isLoading true until the streams are "done" is hard because we don't await them easily.
    // Let's just set _isLoading = false after a short delay to simulate "setup" or just remove _isLoading usage for "emptiness".

    // Revised approach:
    // Show skeletons if list is empty AND we haven't received any data yet?
    // Let's just set _isLoading = false because we want to show the list building up.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Discover',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        HeaderIconButton(
                          icon: LucideIcons.search,
                          onTap: () => context.push('/search'),
                        ),
                        const SizedBox(width: 12),
                        HeaderIconButton(icon: LucideIcons.user, onTap: () {}),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Popular Now Section Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Popular Now',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Popular Now List (Horizontal)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: _popularGames.isEmpty
                    ? ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: 4, // Show 4 skeletons while loading/empty
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) =>
                            const SkeletonGameCardHorizontal(),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: _popularGames.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          return GameCardHorizontal(game: _popularGames[index]);
                        },
                      ),
              ),
            ),

            // Newly Added Section Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Newly Added',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Newly Added Grid
            _newlyAddedGames.isEmpty
                ? SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return const SkeletonGameCardVertical();
                      }, childCount: 6), // Show 6 skeletons while loading/empty
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return GameCardVertical(game: _newlyAddedGames[index]);
                      }, childCount: _newlyAddedGames.length),
                    ),
                  ),

            // Bottom Padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}
