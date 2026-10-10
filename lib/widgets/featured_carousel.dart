import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

/// Large rotating banner for the top popular games.
class FeaturedCarousel extends StatefulWidget {
  final List<Game> games;
  final bool loading;

  const FeaturedCarousel({
    super.key,
    required this.games,
    this.loading = false,
  });

  @override
  State<FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<FeaturedCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || widget.games.length < 2 || !_controller.hasClients) {
        return;
      }
      _controller.animateToPage(
        (_page + 1) % widget.games.length,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (widget.games.isEmpty) return;
    _controller.animateToPage(
      (_page + delta) % widget.games.length,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final height = wide ? 340.0 : 230.0;

    if (widget.games.isEmpty) {
      return SizedBox(
        height: height,
        child: widget.loading
            ? Shimmer.fromColors(
                baseColor: AppTheme.surfaceHighlight,
                highlightColor: Colors.white12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    }

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.games.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _FeaturedSlide(game: widget.games[i]),
          ),
          Positioned(
            bottom: 14,
            right: 18,
            child: Row(
              children: [
                for (var i = 0; i < widget.games.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(left: 6),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppTheme.primaryGreen
                          : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          if (wide && widget.games.length > 1) ...[
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _Arrow(LucideIcons.chevronLeft, () => _go(-1)),
              ),
            ),
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _Arrow(LucideIcons.chevronRight, () => _go(1)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Arrow(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black45,
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
    ),
  );
}

class _FeaturedSlide extends StatelessWidget {
  final Game game;
  const _FeaturedSlide({required this.game});

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final genres = (game.genre ?? '')
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty && g != 'Popular')
        .take(3)
        .toList();

    return GestureDetector(
      onTap: () => openGame(context, game),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (game.coverUrl.isNotEmpty)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: CachedNetworkImage(
                  cacheManager: appImageCache,
                  imageUrl: game.coverUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 300,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xEE050505), Color(0x99050505)],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(wide ? 28 : 16),
              child: Row(
                children: [
                  AspectRatio(
                    aspectRatio: 0.72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: game.coverUrl.isEmpty
                          ? Container(color: AppTheme.surfaceHighlight)
                          : CachedNetworkImage(
                              cacheManager: appImageCache,
                              imageUrl: game.coverUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 500,
                            ),
                    ),
                  ),
                  SizedBox(width: wide ? 28 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.flame,
                                size: 12,
                                color: Colors.black,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'POPULAR',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          game.title,
                          maxLines: wide ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: wide ? 28 : 18,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Chip(
                              LucideIcons.hardDrive,
                              game.repackSize ?? game.size,
                            ),
                            if (wide)
                              for (final g in genres) _Chip(null, g),
                          ],
                        ),
                        if (wide) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => openGame(context, game),
                            icon: const Icon(LucideIcons.download, size: 18),
                            label: const Text('View & download'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData? icon;
  final String text;
  const _Chip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppTheme.primaryGreen),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
