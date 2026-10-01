import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ride_track/services/api_service.dart';
import 'package:ride_track/services/local_storage_service.dart';
import 'package:ride_track/services/rider_service.dart';

class _Client implements HttpClient {
  _Client(this.client, this.origin);
  final HttpClient client;
  final Uri origin;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => client.postUrl(origin);
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.init();
  });

  test(
    'complete refresh persists both categories; invalid refresh preserves snapshot',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic> groups = {
        '40': [
          {'rider_id': '123', 'rider_name': 'Local Rider', 'category': '40'},
        ],
        '100': [
          {'rider_id': '456', 'rider_name': 'Long Rider', 'category': '100'},
        ],
      };
      var failCheckpoints = false;
      final firstRequests = <String>{};
      final requests = <String>[];
      final bothStarted = Completer<void>();
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        requests.add(body['action'] as String);
        firstRequests.add(body['action'] as String);
        if (firstRequests.length == 2 && !bothStarted.isCompleted) {
          bothStarted.complete();
        }
        // Neither response is released until both downloads have started.
        await bothStarted.future.timeout(const Duration(seconds: 5));
        if (body['action'] == 'getCheckpoints') {
          if (failCheckpoints) {
            request.response.write(
              jsonEncode({
                'status': 'error',
                'message': 'Checkpoint download failed',
              }),
            );
            await request.response.close();
            return;
          }
          request.response.write(
            jsonEncode({
              'status': 'success',
              'checkpoints': [
                {
                  'checkpoint_id': 'CP1',
                  'checkpoint_name': 'Start',
                  'category': '40&100',
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }
        expect(body['action'], 'getRiders');
        request.response.write(
          jsonEncode({'status': 'success', 'riders': groups}),
        );
        await request.response.close();
      });
      Future<String?> refresh({
        bool riders = true,
        bool checkpoints = true,
      }) async {
        final clients = List.generate(3, (_) => HttpClient());
        var index = 0;
        try {
          return await HttpOverrides.runZoned(
            () {
              final result = RiderService.refresh(
                downloadRiders: riders,
                downloadCheckpoints: checkpoints,
              );
              if (riders) {
                final pending = RiderService.riderDownload;
                expect(pending, isNotNull);
                expect(
                  identical(RiderService.downloadRiderList(), pending),
                  isTrue,
                );
              }
              return result;
            },
            createHttpClient: (_) => _Client(
              clients[index++],
              Uri.parse('http://127.0.0.1:${server.port}/'),
            ),
          );
        } finally {
          for (final client in clients) {
            client.close(force: true);
          }
        }
      }

      try {
        await refresh();
        expect(LocalStorageService.checkpoints.single.name, 'Start');
        var saved = LocalStorageService.riderList!;
        expect(identical(saved, LocalStorageService.riderList), isTrue);
        await LocalStorageService.init();
        expect(identical(saved, LocalStorageService.riderList), isTrue);
        expect(saved.riders.keys, ['123', '456']);
        expect(saved.riders['456']!.category, '100');
        final savedCheckpoints = LocalStorageService.checkpoints;
        failCheckpoints = true;
        expect(await refresh(), contains('Rider master updated successfully'));
        expect(identical(LocalStorageService.riderList, saved), isFalse);
        saved = LocalStorageService.riderList!;
        expect(
          identical(LocalStorageService.checkpoints, savedCheckpoints),
          isTrue,
        );
        failCheckpoints = false;
        final beforeRetry = requests.length;
        expect(await refresh(riders: false), isNull);
        expect(requests.sublist(beforeRetry), ['getCheckpoints']);
        expect(identical(LocalStorageService.riderList, saved), isTrue);
        for (final invalid in [
          {'40': groups['40']},
          {
            '40': groups['40'],
            '100': [
              {'rider_id': '123', 'rider_name': 'Duplicate', 'category': '100'},
            ],
          },
          {
            '40': groups['40'],
            '100': [
              {'rider_id': '', 'rider_name': 'Invalid', 'category': '100'},
            ],
          },
        ]) {
          groups = invalid;
          await expectLater(refresh(), throwsA(isA<ApiException>()));
          expect(LocalStorageService.riderList!.toJson(), saved.toJson());
          expect(
            identical(LocalStorageService.checkpoints, savedCheckpoints),
            isFalse,
          );
        }
      } finally {
        await server.close(force: true);
      }
    },
  );
}
