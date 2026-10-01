import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ride_track/services/scan_history_service.dart';
import 'scan_history_test.dart' show Client;

void main() {
  late Directory dir;
  late HttpServer server;
  late Future<void> Function(HttpRequest) respond;
  final clients = <HttpClient>[];

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('scan_queue_test');
    await databaseFactory.setDatabasesPath(dir.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request));
  });
  tearDown(() async {
    ScanHistoryService.stopAutomaticSync();
    for (final client in clients) {
      client.close(force: true);
    }
    clients.clear();
    await ScanHistoryService.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> record(String rider) =>
      ScanHistoryService.record(
        riderId: rider,
        riderName: 'Rider $rider',
        category: '40',
        checkpoint: 'Start',
        scannedBy: '123',
      );
  Future<void> network(Future<void> Function() run) {
    final parent = Zone.current;
    return HttpOverrides.runZoned(
      run,
      createHttpClient: (_) {
        final inner = parent.run(() => HttpClient());
        clients.add(inner);
        return Client(inner, Uri.parse('http://127.0.0.1:${server.port}/'));
      },
    );
  }

  Future<void> reply(
    HttpRequest request,
    List<dynamic> entries, {
    Map<String, String> errors = const {},
  }) async {
    request.response.write(
      jsonEncode({
        'status': 'success',
        'confirmed_ids': entries
            .where((e) => !errors.containsKey(e['entry_id']))
            .map((e) => e['entry_id'])
            .toList(),
        'errors': errors,
      }),
    );
    await request.response.close();
  }

  test(
    'pending uploads retain rejections; manual sync can repair them',
    () async {
      final first = await record('1');
      final second = await record('2');
      var reject = true;
      var requests = 0;
      respond = (request) async {
        requests++;
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['action'], 'syncScans');
        await reply(
          request,
          body['entries'],
          errors: reject
              ? {second['entry_id'] as String: 'Invalid checkpoint'}
              : {},
        );
      };
      await network(ScanHistoryService.syncPending);
      expect(ScanHistoryService.queueStatus.value.pending, 0);
      expect(ScanHistoryService.queueStatus.value.rejected, 1);
      final saved = await ScanHistoryService.entries();
      expect(
        saved.firstWhere(
          (e) => e['entry_id'] == first['entry_id'],
        )['confirmed'],
        true,
      );
      await network(ScanHistoryService.syncPending);
      expect(
        requests,
        1,
        reason: 'automatic uploads skip confirmed and rejected rows',
      );
      await ScanHistoryService.close();
      expect((await ScanHistoryService.entries()).first['rejected'], true);
      reject = false;
      await network(ScanHistoryService.sync);
      expect(requests, 2);
      expect(ScanHistoryService.queueStatus.value.rejected, 0);
      expect(
        (await ScanHistoryService.entries()).every(
          (e) => e['confirmed'] == true,
        ),
        true,
      );
    },
  );

  test(
    'slow upload allows recording; manual sync waits and reconciles new rows',
    () async {
      await record('1');
      final started = Completer<void>();
      final release = Completer<void>();
      var requests = 0;
      var active = 0;
      respond = (request) async {
        active++;
        expect(active, 1, reason: 'upload operations must be serialized');
        requests++;
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        if (requests == 1) {
          started.complete();
          await release.future;
        } else {
          expect((body['entries'] as List).length, 2);
        }
        await reply(request, body['entries']);
        active--;
      };
      await network(() async {
        final upload = ScanHistoryService.syncPending();
        await started.future;
        expect(identical(upload, ScanHistoryService.syncPending()), true);
        await record('2').timeout(const Duration(seconds: 2));
        var manualDone = false;
        final manual = ScanHistoryService.sync().then((_) => manualDone = true);
        expect(manualDone, false);
        release.complete();
        await upload;
        await manual;
      });
      expect(requests, 2);
      expect(
        (await ScanHistoryService.entries()).every(
          (e) => e['confirmed'] == true,
        ),
        true,
      );
    },
  );

  test(
    'automatic worker retains failed upload and recovers after restart',
    () async {
      final entry = await record('1');
      var fail = true;
      final seenIds = <String>[];
      respond = (request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        seenIds.add((body['entries'] as List).single['entry_id'] as String);
        if (fail) {
          request.response.statusCode = 503;
          await request.response.close();
        } else {
          await reply(request, body['entries']);
        }
      };
      Future<void> runUntil(bool Function(ScanQueueStatus) condition) async {
        final done = Completer<void>();
        void listener() {
          if (condition(ScanHistoryService.queueStatus.value) &&
              !done.isCompleted) {
            ScanHistoryService.stopAutomaticSync();
            done.complete();
          }
        }

        ScanHistoryService.queueStatus.addListener(listener);
        try {
          await network(() async {
            ScanHistoryService.startAutomaticSync();
            await done.future.timeout(const Duration(seconds: 5));
          });
        } finally {
          ScanHistoryService.queueStatus.removeListener(listener);
          ScanHistoryService.stopAutomaticSync();
        }
      }

      await runUntil((s) => s.error != null && !s.uploading);
      expect((await ScanHistoryService.entries()).single['confirmed'], false);
      await ScanHistoryService.close();
      fail = false;
      await runUntil((s) => s.pending == 0 && s.error == null && !s.uploading);
      expect(seenIds, [entry['entry_id'], entry['entry_id']]);
      expect((await ScanHistoryService.entries()).single['confirmed'], true);
    },
  );
  test('automatic retry backs off after a network failure', () async {
    await record('1');
    var requests = 0;
    final clock = Stopwatch()..start();
    final done = Completer<void>();
    respond = (request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      if (requests == 1) {
        request.response.statusCode = 503;
        await request.response.close();
      } else {
        expect(clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 4)));
        await reply(request, body['entries']);
      }
    };
    void listener() {
      final status = ScanHistoryService.queueStatus.value;
      if (requests == 2 &&
          status.pending == 0 &&
          !status.uploading &&
          !done.isCompleted) {
        ScanHistoryService.stopAutomaticSync();
        done.complete();
      }
    }

    ScanHistoryService.queueStatus.addListener(listener);
    try {
      await network(() async {
        ScanHistoryService.startAutomaticSync();
        await done.future.timeout(const Duration(seconds: 10));
      });
    } finally {
      ScanHistoryService.queueStatus.removeListener(listener);
      ScanHistoryService.stopAutomaticSync();
    }
    expect(requests, 2);
  });

  test(
    'partial batch failure retries only remaining pending entries',
    () async {
      for (var i = 0; i < 51; i++) {
        await record('$i');
      }
      final sizes = <int>[];
      var fail = true;
      respond = (request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final entries = body['entries'] as List;
        sizes.add(entries.length);
        if (entries.length == 1 && fail) {
          request.response.statusCode = 503;
          await request.response.close();
        } else {
          await reply(request, entries);
        }
      };
      await expectLater(
        network(ScanHistoryService.syncPending),
        throwsException,
      );
      expect(ScanHistoryService.queueStatus.value.pending, 1);
      await ScanHistoryService.close();
      fail = false;
      await network(ScanHistoryService.syncPending);
      expect(sizes, [50, 1, 1]);
      expect(ScanHistoryService.queueStatus.value.pending, 0);
    },
  );
}
