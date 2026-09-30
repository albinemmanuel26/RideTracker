import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_track/services/api_service.dart';

// Keep real dart:io responses so the test exercises its POST/302 semantics.
class _LocalClient implements HttpClient {
  _LocalClient(this.client, this.origin);

  final HttpClient client;
  final Uri origin;

  @override
  Future<HttpClientRequest> postUrl(Uri url) => client.postUrl(origin);

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      client.getUrl(origin.resolve(url.path));

  @override
  void close({bool force = false}) => client.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scenario in [
    'html',
    'empty',
    '503',
    'persistent',
    'invalid-pin',
    'sign-in',
  ]) {
    test(
      'login handles $scenario response with bounded safe retries',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final clients = List.generate(3, (_) => HttpClient());
        var clientIndex = 0;
        final methods = <String>[];
        var attempts = 0;
        server.listen((request) async {
          methods.add(request.method);
          final raw = await utf8.decoder.bind(request).join();
          if (request.method == 'POST') {
            attempts++;
            expect(jsonDecode(raw)['action'], 'loginVolunteer');
            request.response.statusCode = 302;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              scenario == 'sign-in'
                  ? 'https://accounts.google.com/login'
                  : 'https://script.googleusercontent.com/result',
            );
          } else if (scenario == 'invalid-pin') {
            request.response.write(
              jsonEncode({'status': 'error', 'message': 'Invalid PIN'}),
            );
          } else if (scenario == 'persistent' || attempts == 1) {
            if (scenario == '503') request.response.statusCode = 503;
            request.response.write(
              scenario == 'empty' ? '' : '<html>Unavailable</html>',
            );
          } else {
            request.response.write(
              jsonEncode({
                'status': 'success',
                'volunteer': {
                  'name': 'Test',
                  'phone': '123',
                  'role': 'scanner',
                },
              }),
            );
          }
          await request.response.close();
        });
        try {
          await HttpOverrides.runZoned(
            () async {
              final login = ApiService.loginVolunteer(phone: '123', pin: '456');
              if (['persistent', 'invalid-pin', 'sign-in'].contains(scenario)) {
                await expectLater(
                  login,
                  throwsA(
                    isA<ApiException>().having(
                      (e) => e.message,
                      'message',
                      contains(
                        scenario == 'persistent'
                            ? 'unexpected response'
                            : scenario == 'invalid-pin'
                            ? 'Invalid PIN'
                            : 'Google sign-in',
                      ),
                    ),
                  ),
                );
              } else {
                expect((await login).name, 'Test');
              }
            },
            createHttpClient: (_) => _LocalClient(
              clients[clientIndex++],
              Uri.parse('http://127.0.0.1:${server.port}/'),
            ),
          );
          final expectedAttempts = scenario == 'persistent'
              ? 3
              : ['invalid-pin', 'sign-in'].contains(scenario)
              ? 1
              : 2;
          expect(attempts, expectedAttempts);
          expect(methods, [
            for (var i = 0; i < expectedAttempts; i++) ...[
              'POST',
              if (scenario != 'sign-in') 'GET',
            ],
          ]);
        } finally {
          for (final client in clients) {
            client.close(force: true);
          }
          await server.close(force: true);
        }
      },
    );
  }
  for (final code in [503, 403, 404]) {
    test('read-only retry limit for HTTP $code', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final clients = List.generate(3, (_) => HttpClient());
      final arrivals = <int>[];
      final clock = Stopwatch()..start();
      var index = 0;
      server.listen((request) async {
        await request.drain<void>();
        arrivals.add(clock.elapsedMilliseconds);
        request.response.statusCode = code;
        await request.response.close();
      });
      try {
        await HttpOverrides.runZoned(
          () async {
            await expectLater(
              ApiService.getCheckpoints(),
              throwsA(isA<ApiException>()),
            );
          },
          createHttpClient: (_) => _LocalClient(
            clients[index++],
            Uri.parse('http://127.0.0.1:${server.port}/'),
          ),
        );
        expect(arrivals.length, code == 503 ? 3 : 1);
        if (code == 503) {
          expect(arrivals[1] - arrivals[0], greaterThanOrEqualTo(950));
          expect(arrivals[2] - arrivals[1], greaterThanOrEqualTo(1950));
        }
      } finally {
        for (final client in clients) {
          client.close(force: true);
        }
        await server.close(force: true);
      }
    });
  }
  for (final code in [200, 404, 503]) {
    test('uncertain scan HTTP $code does not retry or query history', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      final actions = <String>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        actions.add(body['action'] as String);
        request.response.statusCode = code;
        request.response.write('<html>Unavailable</html>');
        await request.response.close();
      });
      try {
        await HttpOverrides.runZoned(
          () async {
            await expectLater(
              ApiService.scanCheckpoint(
                riderId: '123',
                category: '40',
                checkpoint: 'Start',
                scannedBy: '456',
              ),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.message,
                  'message',
                  contains('Retrying may create another'),
                ),
              ),
            );
          },
          createHttpClient: (_) => _LocalClient(
            client,
            Uri.parse('http://127.0.0.1:${server.port}/'),
          ),
        );
        expect(actions, ['scanCheckpoint']);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });
  }
  for (final action in [
    'loginVolunteer',
    'getCheckpoints',
    'verifyRider',
    'scanCheckpoint',
  ]) {
    test(
      '$action follows POST 302 and subsequent GET 302 without replaying POST',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = HttpClient();
        final methods = <String>[];
        final bodies = <String>[];
        server.listen((request) async {
          methods.add(request.method);
          bodies.add(await request.map(String.fromCharCodes).join());
          if (methods.length < 3) {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              'https://script.googleusercontent.com/result${methods.length}',
            );
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'status': 'success',
                'volunteer': {
                  'name': 'Test',
                  'phone': '123',
                  'role': 'scanner',
                },
                'checkpoints': [
                  {'checkpoint_id': 'CP1', 'checkpoint_name': 'Test'},
                ],
                'data': {'rider_name': 'Test', 'rider_id': 'R1'},
              }),
            );
          }
          await request.response.close();
        });
        try {
          final result = await HttpOverrides.runZoned(
            () async {
              switch (action) {
                case 'loginVolunteer':
                  return (await ApiService.loginVolunteer(
                    phone: '123',
                    pin: '456',
                  )).name;
                case 'getCheckpoints':
                  return (await ApiService.getCheckpoints()).single.name;
                case 'verifyRider':
                  return (await ApiService.verifyRider(
                    riderId: 'R1',
                  ))['rider_name'];
                default:
                  return (await ApiService.scanCheckpoint(
                    riderId: 'R1',
                    category: '100',
                    checkpoint: 'CP1',
                    scannedBy: '123',
                  ))['rider_name'];
              }
            },
            createHttpClient: (_) => _LocalClient(
              client,
              Uri.parse('http://127.0.0.1:${server.port}/'),
            ),
          );
          expect(result, 'Test');
          expect(methods, ['POST', 'GET', 'GET']);
          expect(jsonDecode(bodies.first)['action'], action);
          expect(bodies.skip(1), everyElement(isEmpty));
        } finally {
          client.close(force: true);
          await server.close(force: true);
        }
      },
    );
  }
}
