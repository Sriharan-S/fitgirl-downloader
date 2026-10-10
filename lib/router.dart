import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/screens/discover_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/downloads_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/game_details_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/game_download_details_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/library_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/search_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/select_files_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/settings_screen.dart';
import 'package:fitgirl_mobile_flutter/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Game details live inside every tab so the navigation (bottom bar or
/// desktop sidebar) stays visible.
GoRoute _gameRoute() => GoRoute(
  path: 'game',
  builder: (context, state) => GameDetailsScreen(
    gameId: state.uri.queryParameters['id'],
    initialGame: state.extra is Game ? state.extra as Game : null,
  ),
);

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DiscoverScreen(),
              routes: [_gameRoute()],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
              routes: [_gameRoute()],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
              routes: [_gameRoute()],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/downloads',
              builder: (context, state) => const DownloadsScreen(),
              routes: [
                _gameRoute(),
                GoRoute(
                  path: 'details',
                  builder: (context, state) => GameDownloadDetailsScreen(
                    gameTitle: state.uri.queryParameters['title'] ?? '',
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/select-files',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null) {
          return const Scaffold(body: Center(child: Text('Error: No files')));
        }
        return SelectFilesScreen(
          game: extra['game'] as Game,
          fileUrls: List<String>.from(extra['fileUrls'] as List),
          initialSelection: (extra['initialSelection'] as List?)
              ?.cast<String>(),
          completedFiles: (extra['completedFiles'] as List?)?.cast<String>(),
        );
      },
    ),
  ],
);

/// Opens a game's details page inside the current tab.
void openGame(BuildContext context, Game game) {
  final path = GoRouterState.of(context).uri.path;
  var base = '';
  for (final tab in const ['/search', '/library', '/downloads']) {
    if (path.startsWith(tab)) base = tab;
  }
  context.push(
    '$base/game?id=${Uri.encodeQueryComponent(game.url)}',
    extra: game,
  );
}

/// Opens a game's download page; switches to the Downloads tab if needed.
void openDownloadDetails(BuildContext context, String gameTitle) {
  final location =
      '/downloads/details?title=${Uri.encodeQueryComponent(gameTitle)}';
  if (GoRouterState.of(context).uri.path.startsWith('/downloads')) {
    context.push(location);
  } else {
    context.go(location);
  }
}
