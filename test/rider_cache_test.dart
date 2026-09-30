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
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['action'], 'getRiders');
        request.response.write(
          jsonEncode({'status': 'success', 'riders': groups}),
        );
        await request.response.close();
      });
      Future<void> refresh() {
        final client = HttpClient();
        return HttpOverrides.runZoned(
          RiderService.refresh,
          createHttpClient: (_) =>
              _Client(client, Uri.parse('http://127.0.0.1:${server.port}/')),
        );
      }

      try {
        await refresh();
        final saved = LocalStorageService.riderList!;
        expect(saved.riders.keys, ['123', '456']);
        expect(saved.riders['456']!.category, '100');
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
        }
      } finally {
        await server.close(force: true);
      }
    },
  );
}
