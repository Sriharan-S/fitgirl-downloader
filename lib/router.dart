import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fitgirl_mobile_flutter/screens/discover_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/search_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/library_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/downloads_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/game_details_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/select_files_screen.dart';
import 'package:fitgirl_mobile_flutter/widgets/bottom_nav.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: BottomNav(navigationShell: navigationShell),
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DiscoverScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/downloads',
              builder: (context, state) => const DownloadsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/game-details',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = state.uri.queryParameters['id'];
        return GameDetailsScreen(gameId: id);
      },
    ),
    GoRoute(
      path: '/select-files',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null) {
          // Ideally handle error or  redirect
          return const Scaffold(body: Center(child: Text('Error: No files')));
        }
        return SelectFilesScreen(
          game: extra['game'],
          fileUrls: extra['fileUrls'],
        );
      },
    ),
  ],
);
