import 'dart:async';
import 'dart:io';

import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/screens/discover_screen.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:fitgirl_mobile_flutter/widgets/skeleton_game_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String dir;
  _FakePaths(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Game _game(String title) => Game(
  id: 'https://fitgirl-repacks.site/$title/',
  url: 'https://fitgirl-repacks.site/$title/',
  title: title,
  coverUrl: '',
  size: '10 GB',
  genre: 'Action',
);

String _page(String title) =>
    '<h1 class="entry-title">$title</h1><div class="entry-content">'
    '<p>Genres/Tags: Action</p><p>Repack Size: <strong>10 GB</strong></p></div>';

void main() {
  late Directory tmp;
  final network = Completer<void>();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('cache-test-');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    // The network answers only when the test allows it.
    ScraperService().client = WebClient(
      maxConcurrent: 8,
      inner: MockClient((req) async {
        await network.future;
        final u = req.url.toString();
        if (u.endsWith('/popular-repacks/')) {
          return http.Response(
            '<a class="bump-view" href="https://fitgirl-repacks.site/fresh-popular/" title="x">x</a>',
            200,
          );
        }
        if (u.endsWith('sitemap_index.xml')) {
          return http.Response(
            '<sitemapindex><sitemap><loc>https://fitgirl-repacks.site/post-sitemap9.xml</loc></sitemap></sitemapindex>',
            200,
          );
        }
        if (u.endsWith('post-sitemap9.xml')) {
          return http.Response(
            '<urlset><url><loc>https://fitgirl-repacks.site/fresh-new/</loc></url></urlset>',
            200,
          );
        }
        if (u.contains('fresh-popular')) {
          return http.Response(_page('Fresh Popular Game'), 200);
        }
        if (u.contains('fresh-new')) {
          return http.Response(_page('Fresh New Game'), 200);
        }
        return http.Response('', 404);
      }),
    );
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('Discover shows the cache instantly, then fresh data quietly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await CacheStore().writeList('popular', [
        for (var i = 0; i < 6; i++) _game('Cached Popular $i'),
      ]);
      await CacheStore().writeList('newly', [_game('Cached New Game')]);
    });

    // Start the screen in real time so its file reads complete.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const DiscoverScreen(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // Cached data is on screen right away, with no skeletons.
    expect(find.text('Cached New Game', skipOffstage: false), findsOneWidget);
    expect(find.text('Cached Popular 0', skipOffstage: false), findsOneWidget);
    expect(
      find.byType(SkeletonGameCardVertical, skipOffstage: false),
      findsNothing,
    );

    // The network finishes: fresh games replace the lists, still no skeletons.
    network.complete();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Fresh New Game', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Cached New Game', skipOffstage: false),
      findsOneWidget,
    ); // older items kept below
    expect(
      find.byType(SkeletonGameCardVertical, skipOffstage: false),
      findsNothing,
    );

    // And the fresh lists were cached for next time.
    final saved = await tester.runAsync(() => CacheStore().readList('newly'));
    expect(saved!.first.title, 'Fresh New Game');

    await tester.pump(const Duration(seconds: 2)); // delayed permission check
  });
}
