import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/widgets/hoverable.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Wide "featured" card used in the Popular carousel.
class GameCardHorizontal extends StatelessWidget {
  final Game game;
  final double width;

  const GameCardHorizontal({super.key, required this.game, this.width = 300});

  @override
  Widget build(BuildContext context) {
    final hasCover = game.coverUrl.isNotEmpty;
    return SizedBox(
      width: width,
      child: HoverCard(
        onTap: () => openGame(context, game),
        tooltip: game.title,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (hasCover)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: CachedNetworkImage(
                      imageUrl: game.coverUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              game.genre ?? 'Popular',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            game.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.hardDrive,
                                  color: AppTheme.primaryGreen,
                                  size: 10,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    game.size,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 0.7,
                    child: hasCover
                        ? CachedNetworkImage(
                            imageUrl: game.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            errorWidget: (_, _, _) => const Icon(
                              LucideIcons.gamepad2,
                              color: Colors.white24,
                            ),
                          )
                        : const Icon(
                            LucideIcons.gamepad2,
                            color: Colors.white24,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
