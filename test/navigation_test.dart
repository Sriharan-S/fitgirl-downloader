import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _location() => router.routerDelegate.currentConfiguration.uri.toString();

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _frames(tester);
}

/// Fixed frames: Discover's loading animations never "settle".
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Android back: nested page, tab root, then exit prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DownloadService().sessionsNotifier.value = [
      DownloadSession(
        gameTitle: 'Game',
        coverUrl: '',
        createdAt: DateTime(2026),
        files: const [DownloadFile(url: 'u', name: 'u.bin')],
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ),
    );

    router.go('/downloads');
    await _frames(tester);
    router.push('/downloads/details?title=Game');
    await _frames(tester);
    expect(find.text('Download details'), findsOneWidget);

    await _back(tester); // nested page -> its tab
    expect(find.text('Download details'), findsNothing);
    expect(_location(), '/downloads');

    await _back(tester); // tab root -> Discover
    expect(_location(), '/');

    await _back(tester); // Discover -> confirm exit
    expect(find.text('Exit FitGirl Downloader?'), findsOneWidget);
    expect(
      find.text('Downloads keep running in the background.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Stay'));
    await _frames(tester);
    expect(find.text('Exit FitGirl Downloader?'), findsNothing);
    expect(_location(), '/');

    // Every tab shows its label; selection doesn't change the layout.
    for (final label in [
      'Discover',
      'Search',
      'Library',
      'Downloads',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    // Let the Discover screen's delayed permission check finish.
    await tester.pump(const Duration(seconds: 2));
  });
}
