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
  for (final recorded in [true, false, null]) {
    test(
      'recovers scan 404 with status=$recorded without replaying scan',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = HttpClient();
        final statusClient = HttpClient();
        final secondStatusClient = HttpClient();
        var clientIndex = 0;
        final actions = <String>[];
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          actions.add(body['action'] as String);
          if (body['action'] == 'scanCheckpoint') {
            request.response.statusCode = 404;
          } else {
            request.response.write(
              jsonEncode(
                recorded == null
                    ? {'status': 'error'}
                    : {'status': 'success', 'recorded': recorded},
              ),
            );
          }
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
                  recorded == true
                      ? isA<DuplicateScanException>()
                      : isA<ApiException>().having(
                          (e) => e.message,
                          'message',
                          contains(
                            recorded == false
                                ? 'No check-in found yet'
                                : 'Could not confirm',
                          ),
                        ),
                ),
              );
            },
            createHttpClient: (_) => _LocalClient(
              [client, statusClient, secondStatusClient][clientIndex++],
              Uri.parse('http://127.0.0.1:${server.port}/'),
            ),
          );
          expect(actions, [
            'scanCheckpoint',
            'checkScanStatus',
            if (recorded != true) 'checkScanStatus',
          ]);
        } finally {
          statusClient.close(force: true);
          secondStatusClient.close(force: true);
          client.close(force: true);
          await server.close(force: true);
        }
      },
    );
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
