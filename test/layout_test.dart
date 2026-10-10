import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/screens/downloads_screen.dart';
import 'package:fitgirl_mobile_flutter/screens/game_download_details_screen.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadSession _demo(String title, {bool paused = false}) => DownloadSession(
  gameTitle: title,
  coverUrl: '',
  totalGameSize: 'from 25.4 GB',
  createdAt: DateTime(2026, 10, 1),
  isPaused: paused,
  originalUrls: [
    for (var i = 1; i <= 30; i++)
      'https://fuckingfast.co/x$i#$title.part$i.rar',
  ],
  files: [
    for (var i = 1; i <= 30; i++)
      DownloadFile(
        url: 'https://fuckingfast.co/x$i#$title.part$i.rar',
        name: '$title-a-very-long-file-name-that-should-ellipsize.part$i.rar',
        status: i <= 10
            ? FileStatus.completed
            : i <= 12
            ? (paused ? FileStatus.paused : FileStatus.downloading)
            : i == 13
            ? FileStatus.failed
            : FileStatus.queued,
        progress: i <= 10 ? 1 : (i <= 12 ? 0.4 : 0),
        expectedSize: 500 * 1024 * 1024,
        speed: i <= 12 && !paused ? 8.5 : 0,
        error: i == 13 ? 'HTTP 403' : null,
      ),
  ],
);

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: ThemeData.dark(), home: child),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    DownloadService().sessionsNotifier.value = [
      _demo('Some Really Long Game Title: The Definitive Edition'),
      _demo('Paused Game', paused: true),
    ];
  });

  testWidgets('Downloads: phone layout shows a list without overflow', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(360, 780), const DownloadsScreen());
    expect(find.byType(SessionCard), findsNWidgets(2));
    expect(find.byType(DownloadDetailsView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Downloads: desktop layout shows master/detail', (tester) async {
    await _pumpAt(tester, const Size(1440, 900), const DownloadsScreen());
    expect(find.byType(SessionCard), findsNWidgets(2));
    expect(find.byType(DownloadDetailsView), findsOneWidget);
    expect(find.text('Add / remove files'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Selecting another game swaps the detail pane.
    await tester.tap(find.text('Paused Game').first);
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Download details: narrow page renders all sections', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(360, 780),
      const Scaffold(
        body: DownloadDetailsView(
          gameTitle: 'Some Really Long Game Title: The Definitive Edition',
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Files'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Files'), findsOneWidget);
    expect(find.textContaining('Failed 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
