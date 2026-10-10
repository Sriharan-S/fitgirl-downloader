import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/widgets/hoverable.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Compact row used for search results.
class GameListTile extends StatelessWidget {
  final Game game;

  const GameListTile({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: () => openGame(context, game),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 60,
              height: 84,
              child: game.coverUrl.isEmpty
                  ? _placeholder()
                  : CachedNetworkImage(
                      imageUrl: game.coverUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 180,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.surfaceHighlight),
                      errorWidget: (_, _, _) => _placeholder(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (game.genre != null)
                  Text(
                    game.genre!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  game.size,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppTheme.surfaceHighlight,
    child: const Icon(LucideIcons.gamepad2, color: Colors.white24),
  );
}
