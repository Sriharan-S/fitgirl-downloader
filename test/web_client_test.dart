import 'package:fitgirl_mobile_flutter/services/web_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('passes a cookie check that redirects to the same URL', () async {
    final seen = <String?>[];
    final client = WebClient(
      inner: MockClient((req) async {
        seen.add(req.headers['Cookie']);
        if (req.headers['Cookie']?.contains('__ddg1_=abc') ?? false) {
          return http.Response('<h1 class="entry-title">Game</h1>', 200);
        }
        return http.Response(
          '',
          301,
          headers: {
            'location': req.url.toString(),
            'set-cookie':
                '__ddg1_=abc; Path=/; Expires=Sun, 10-Oct-2027 10:35:14 GMT; HttpOnly',
          },
        );
      }),
    );

    final res = await client.get(
      Uri.parse('https://fitgirl-repacks.site/game/'),
    );
    expect(res.statusCode, 200);
    expect(seen, [null, '__ddg1_=abc']);
  });

  test('sends browser headers and gives up on endless redirects', () async {
    var calls = 0;
    final client = WebClient(
      inner: MockClient((req) async {
        calls++;
        expect(req.headers['User-Agent'], contains('Mozilla/5.0'));
        return http.Response('', 302, headers: {'location': '/loop'});
      }),
    );
    await expectLater(
      client.get(Uri.parse('https://example.com/'), retries: 0),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 10);
  });

  test('retries server errors', () async {
    var calls = 0;
    final client = WebClient(
      inner: MockClient((req) async {
        calls++;
        return calls < 3
            ? http.Response('busy', 503)
            : http.Response('ok', 200);
      }),
    );
    final res = await client.get(Uri.parse('https://example.com/'));
    expect(res.body, 'ok');
    expect(calls, 3);
  });

  test('limits concurrent requests', () async {
    var inFlight = 0;
    var peak = 0;
    final client = WebClient(
      maxConcurrent: 2,
      inner: MockClient((req) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
        return http.Response('ok', 200);
      }),
    );
    await Future.wait([
      for (var i = 0; i < 8; i++)
        client.get(Uri.parse('https://example.com/$i')),
    ]);
    expect(peak, 2);
  });
}
