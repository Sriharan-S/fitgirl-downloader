import 'dart:convert';

import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('FuckingFast', () {
    test('reads the link from the HX-Redirect header of /f/<id>/go', () async {
      late http.Request seen;
      ScraperService().client = WebClient(
        inner: MockClient((req) async {
          seen = req;
          return http.Response(
            'OK',
            200,
            headers: {'hx-redirect': 'https://dl.fuckingfast.co/dl/abc'},
          );
        }),
      );
      final link = await ScraperService().getDirectDownloadLink(
        'https://fuckingfast.co/jvqv32niba75#Game.part01.rar',
      );
      expect(link?.url, 'https://dl.fuckingfast.co/dl/abc');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://fuckingfast.co/f/jvqv32niba75/go');
      expect(seen.headers['HX-Request'], 'true');
    });

    test('a deleted file is a permanent failure', () async {
      ScraperService().client = WebClient(
        inner: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        ScraperService().getDirectDownloadLink('https://fuckingfast.co/gone'),
        throwsA(
          isA<MirrorException>().having((e) => e.permanent, 'permanent', true),
        ),
      );
    });
  });

  group('DataNodes', () {
    String step2({bool captcha = false}) =>
        '<html><body><download-countdown :countdown="0" '
        'code="6jimwv4wv1lc" referer="https://datanodes.to/download" '
        'rand="r123" free-method="Free Download &gt;&gt;" premium-method="" '
        ':has-captcha="$captcha" dl-token="1791640778.0.abc">'
        '</download-countdown></body></html>';

    test(
      'download1, then download2 with the step-2 token; decodes the url',
      () async {
        final posts = <http.Request>[];
        ScraperService().client = WebClient(
          inner: MockClient((req) async {
            if (req.method == 'GET') return http.Response('<html></html>', 200);
            posts.add(req);
            if (req.body.contains('download1')) {
              return http.Response(step2(), 200);
            }
            return http.Response(
              jsonEncode({'url': 'https%3A%2F%2Fcdn.example%2Ff%2FGame.rar'}),
              200,
            );
          }),
        );
        final link = await ScraperService().getDirectDownloadLink(
          'https://datanodes.to/6jimwv4wv1lc/Game.rar',
        );
        expect(link?.url, 'https://cdn.example/f/Game.rar');
        expect(posts, hasLength(2));
        expect(posts[0].bodyFields['op'], 'download1');
        expect(posts[0].bodyFields['fname'], 'Game.rar');
        final second = posts[1];
        expect(second.url.toString(), 'https://datanodes.to/download');
        expect(second.headers['X-Dn-Dl'], '1');
        for (final part in [
          'download2',
          'r123',
          '1791640778.0.abc',
          'Free Download >>',
        ]) {
          expect(second.body, contains(part));
        }
      },
    );

    test('a captcha on step 2 hands over to the browser', () async {
      ScraperService().client = WebClient(
        inner: MockClient((req) async {
          if (req.method == 'GET') return http.Response('<html></html>', 200);
          return http.Response(step2(captcha: true), 200);
        }),
      );
      await expectLater(
        ScraperService().getDirectDownloadLink(
          'https://datanodes.to/6jimwv4wv1lc/Game.rar',
        ),
        throwsA(
          isA<MirrorException>()
              .having((e) => e.permanent, 'permanent', false)
              .having((e) => e.message, 'message', contains('browser check')),
        ),
      );
    });

    test('a missing file is a permanent failure', () async {
      ScraperService().client = WebClient(
        inner: MockClient((_) async => http.Response('File Not Found', 404)),
      );
      await expectLater(
        ScraperService().getDirectDownloadLink(
          'https://datanodes.to/zzzz/Nope.rar',
        ),
        throwsA(
          isA<MirrorException>().having((e) => e.permanent, 'permanent', true),
        ),
      );
    });

    test('the browser script fills in the file code and name', () {
      final js = ScraperService.dataNodesExtractJsForTest(
        'https://datanodes.to/6jimwv4wv1lc/Game.part1.rar',
      );
      expect(js, contains('id: "6jimwv4wv1lc"'));
      expect(js, contains('fname: "Game.part1.rar"'));
      expect(js, isNot(contains('__CODE__')));
      expect(js, contains("'X-Dn-Dl': '1'"));
    });
  });

  test('alternate mirrors match by file name, FuckingFast first', () {
    final game = Game(
      id: 'g',
      title: 'Game',
      url: 'g',
      coverUrl: '',
      size: '1 GB',
      mirrors: {
        'DataNodes':
            'https://datanodes.to/aaa/Game.part1.rar\nhttps://datanodes.to/bbb/Game.part2.rar',
        'FuckingFast':
            'https://fuckingfast.co/x1#Game.part1.rar\nhttps://fuckingfast.co/x2#Game.part2.rar',
      },
    );
    expect(
      ScraperService.alternateMirrorsIn(
        game,
        'https://datanodes.to/bbb/Game.part2.rar',
      ),
      ['https://fuckingfast.co/x2#Game.part2.rar'],
    );
  });
}
