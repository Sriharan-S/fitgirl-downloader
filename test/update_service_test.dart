import 'dart:convert';

import 'package:fitgirl_mobile_flutter/core/app_version.dart';
import 'package:fitgirl_mobile_flutter/services/update_service.dart';
import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:fitgirl_mobile_flutter/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _release(String tag, {bool prerelease = false}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': prerelease,
  'body': '## What changed\n* Fix **downloads**',
  'html_url': 'https://github.com/x/y/releases/tag/$tag',
  'published_at': '2026-10-11T10:00:00Z',
  'assets': [
    {
      'name': 'FitGirl-Downloader-$tag-android-universal.apk',
      'browser_download_url': 'https://example.com/$tag.apk',
      'size': 100,
    },
    {
      'name': 'FitGirl-Downloader-$tag-windows-setup.exe',
      'browser_download_url': 'https://example.com/$tag.exe',
      'size': 200,
    },
  ],
};

void main() {
  late List<Map<String, dynamic>> releases;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 11, 9);
    releases = [];
    UpdateService().configureForTest(
      currentTag: 'v2026.10.10.50',
      now: () => now,
      client: WebClient(
        inner: MockClient(
          (_) async => http.Response(jsonEncode(releases), 200),
        ),
      ),
    );
  });

  group('AppVersion', () {
    test('parses and orders tags', () {
      expect(AppVersion.parse('v2026.10.11.42'), [2026, 10, 11, 42]);
      expect(AppVersion.parse('v2026.10.10'), [2026, 10, 10]);
      expect(AppVersion.parse('v2026.10.11.42-dev-abc1234'), isNull);
      expect(AppVersion.parse('dev'), isNull);
      expect(
        AppVersion.compare([2026, 10, 10], [2026, 10, 10, 1]),
        lessThan(0),
      );
      expect(AppVersion.compare([2026, 10, 11, 2], [2026, 10, 9, 99]), 1);
      expect(AppVersion.label('v2026.10.11.42'), '2026.10.11 (build 42)');
    });
  });

  test('up to date, pre-releases and old releases are ignored', () async {
    releases = [
      _release('v2026.10.12.60', prerelease: true),
      _release('v2026.10.10.50'),
      _release('v2026.10.9'),
    ];
    expect(await UpdateService().check(), isNull);
  });

  test('finds the newest release and the platform installer', () async {
    releases = [_release('v2026.10.11.51'), _release('v2026.10.12.52')];
    final check = (await UpdateService().check())!;
    expect(check.latest.tag, 'v2026.10.12.52');
    expect(check.versionsBehind, 2);
    expect(check.forced, isFalse);
    expect(check.latest.asset?.name, endsWith('-windows-setup.exe'));
  });

  test('prompts at most once a day', () async {
    releases = [_release('v2026.10.11.51')];
    expect(await UpdateService().checkForStartupPrompt(), isNotNull);
    expect(await UpdateService().checkForStartupPrompt(), isNull);
    now = now.add(const Duration(days: 1));
    expect(await UpdateService().checkForStartupPrompt(), isNotNull);
  });

  test('"Later" waits until tomorrow', () async {
    releases = [_release('v2026.10.11.51')];
    await UpdateService().remindLater();
    now = DateTime(2026, 10, 11, 23, 59);
    expect(await UpdateService().checkForStartupPrompt(), isNull);
    now = DateTime(2026, 10, 12, 0, 1);
    expect(await UpdateService().checkForStartupPrompt(), isNotNull);
  });

  test('"Skip" hides that version until a newer one appears', () async {
    releases = [_release('v2026.10.11.51')];
    await UpdateService().skip('v2026.10.11.51');
    now = now.add(const Duration(days: 3));
    expect(await UpdateService().checkForStartupPrompt(), isNull);

    releases = [_release('v2026.10.11.51'), _release('v2026.10.14.53')];
    final check = await UpdateService().checkForStartupPrompt();
    expect(check?.latest.tag, 'v2026.10.14.53');
  });

  test('three releases behind forces the update on every start', () async {
    releases = [
      _release('v2026.10.11.51'),
      _release('v2026.10.12.52'),
      _release('v2026.10.13.53'),
    ];
    await UpdateService().skip('v2026.10.13.53');
    await UpdateService().remindLater();
    final first = await UpdateService().checkForStartupPrompt();
    final second = await UpdateService().checkForStartupPrompt();
    expect(first?.forced, isTrue);
    expect(second?.forced, isTrue);
  });

  test('local builds never check', () async {
    UpdateService().configureForTest(currentTag: 'dev');
    releases = [_release('v2030.1.1.1')];
    expect(await UpdateService().check(), isNull);
    UpdateService().configureForTest(currentTag: 'v2026.10.10.50');
  });

  for (final forced in [false, true]) {
    testWidgets('dialog buttons when forced=$forced', (tester) async {
      final check = UpdateCheck(
        currentTag: 'v2026.10.10.50',
        versionsBehind: forced ? 3 : 1,
        latest: const AppRelease(
          tag: 'v2026.10.11.51',
          version: [2026, 10, 11, 51],
          notes: '## Changes\n* Fix **downloads**',
          pageUrl: 'https://example.com',
          asset: ReleaseAsset(
            'x-windows-setup.exe',
            'https://example.com/x',
            1024,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(context, check),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text(forced ? 'Update required' : 'Update available'),
        findsOneWidget,
      );
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), forced ? findsNothing : findsOneWidget);
      expect(
        find.text('Skip this version'),
        forced ? findsNothing : findsOneWidget,
      );
      expect(find.textContaining('Fix downloads'), findsOneWidget);
    });
  }
}
