import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/widgets/hoverable.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Portrait cover card used in grids. Sized by its parent grid cell.
class GameCardVertical extends StatelessWidget {
  final Game game;

  const GameCardVertical({super.key, required this.game});

  /// Width/height ratio grids should use for this card.
  static const double aspectRatio = 0.6;

  @override
  Widget build(BuildContext context) {
    final genre = game.genre?.split(',').first.trim();
    return HoverCard(
      onTap: () => openGame(context, game),
      tooltip: game.title,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: game.coverUrl.isEmpty
                      ? _placeholder()
                      : CachedNetworkImage(
                          cacheManager: appImageCache,
                          imageUrl: game.coverUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (_, _) =>
                              Container(color: AppTheme.surfaceHighlight),
                          errorWidget: (_, _, _) => _placeholder(),
                        ),
                ),
                if (genre != null && genre.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    right: 6,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          genre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            game.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                LucideIcons.hardDrive,
                size: 11,
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  game.size,
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
    );
  }

  Widget _placeholder() => Container(
    color: AppTheme.surfaceHighlight,
    child: const Center(
      child: Icon(LucideIcons.gamepad2, color: Colors.white24, size: 32),
    ),
  );
}
