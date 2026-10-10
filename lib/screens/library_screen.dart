import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/favorites_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_card_vertical.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _filter = '';

  @override
  void initState() {
    super.initState();
    FavoritesService().getFavorites().then((list) {
      FavoritesService().favoritesNotifier.value = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<List<Game>>(
          valueListenable: FavoritesService().favoritesNotifier,
          builder: (context, savedGames, _) {
            final query = _filter.toLowerCase();
            final games = query.isEmpty
                ? savedGames.reversed.toList()
                : savedGames.reversed
                      .where((g) => g.title.toLowerCase().contains(query))
                      .toList();

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ContentConstraint(
                    child: PageHeader(
                      title: 'Library',
                      overline: 'MY COLLECTION · ${savedGames.length} GAMES',
                    ),
                  ),
                ),
                if (savedGames.isNotEmpty)
                  SliverContent(
                    extraPadding: const EdgeInsets.only(top: 8, bottom: 16),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: TextField(
                            onChanged: (v) => setState(() => _filter = v),
                            decoration: const InputDecoration(
                              hintText: 'Filter saved games',
                              prefixIcon: Icon(LucideIcons.search, size: 18),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (savedGames.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyLibrary(),
                  )
                else
                  SliverContent(
                    extraPadding: const EdgeInsets.only(bottom: 32),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: context.isWide ? 210 : 190,
                        childAspectRatio: GameCardVertical.aspectRatio,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            GameCardVertical(game: games[index]),
                        childCount: games.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.bookmark, size: 56, color: Colors.white12),
          SizedBox(height: 16),
          Text(
            'No saved games',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 6),
          Text(
            'Tap the bookmark on a game page to save it here',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
