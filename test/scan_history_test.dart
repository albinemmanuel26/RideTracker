import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ride_track/services/scan_history_service.dart';

class Client implements HttpClient {
  Client(this.inner, this.uri);
  final HttpClient inner;
  final Uri uri;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => inner.postUrl(uri);
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'upgrade preserves history and blocks concurrent duplicate inserts',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('scan_upgrade_test');
      await databaseFactory.setDatabasesPath(dir.path);
      final old = await openDatabase(
        'scan_history.db',
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE scans (entry_id TEXT PRIMARY KEY, payload TEXT NOT NULL, confirmed INTEGER NOT NULL DEFAULT 0, error TEXT)',
        ),
      );
      for (final id in ['old1', 'old2']) {
        await old.insert('scans', {
          'entry_id': id,
          'payload': jsonEncode({
            'entry_id': id,
            'rider_id': '1',
            'category': '40',
            'checkpoint': 'Start',
          }),
        });
      }
      await old.close();
      try {
        expect((await ScanHistoryService.entries()).length, 2);
        Future<Map<String, dynamic>> record(String rider) =>
            ScanHistoryService.record(
              riderId: rider,
              riderName: 'Rider',
              category: '40',
              checkpoint: 'Start',
              scannedBy: '123',
            );
        await expectLater(
          record('1'),
          throwsA(isA<LocalDuplicateScanException>()),
        );
        final results = await Future.wait(
          List.generate(2, (_) async {
            try {
              await record('2');
              return true;
            } on LocalDuplicateScanException {
              return false;
            }
          }),
        );
        expect(results.where((ok) => ok).length, 1);
        expect((await ScanHistoryService.entries()).length, 3);
      } finally {
        await ScanHistoryService.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'durable local-first record, failed upload and full reconciliation',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('scan_history_test');
      await databaseFactory.setDatabasesPath(dir.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final actions = <String>[];
      server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        actions.add(body['action'] as String);
        if (body['action'] == 'scanCheckpoint') {
          request.response.statusCode = 503;
        } else {
          final entries = body['entries'] as List;
          expect(entries.length, 1);
          request.response.write(
            jsonEncode({
              'status': 'success',
              'confirmed_ids': entries.map((e) => e['entry_id']).toList(),
              'errors': {},
            }),
          );
        }
        await request.response.close();
      });
      try {
        final entry = await ScanHistoryService.record(
          riderId: '1',
          riderName: 'Rider',
          category: '40',
          checkpoint: 'Start',
          scannedBy: '123',
        );
        await expectLater(
          ScanHistoryService.record(
            riderId: '1',
            riderName: 'Rider',
            category: '40',
            checkpoint: 'Start',
            scannedBy: 'another',
          ),
          throwsA(isA<LocalDuplicateScanException>()),
        );
        expect((await ScanHistoryService.entries()).single['confirmed'], false);
        await ScanHistoryService.close();
        expect(
          (await ScanHistoryService.entries()).single['entry_id'],
          entry['entry_id'],
        );
        Future<void> network(Future<void> Function() run) {
          final client = HttpClient();
          return HttpOverrides.runZoned(
            run,
            createHttpClient: (_) =>
                Client(client, Uri.parse('http://127.0.0.1:${server.port}/')),
          );
        }

        await expectLater(
          network(() => ScanHistoryService.submit(entry)),
          throwsException,
        );
        expect((await ScanHistoryService.entries()).single['confirmed'], false);
        await network(ScanHistoryService.sync);
        expect((await ScanHistoryService.entries()).single['confirmed'], true);
        await network(
          ScanHistoryService.sync,
        ); // confirmed rows are compared too
        await expectLater(
          ScanHistoryService.record(
            riderId: ' 1 ',
            riderName: 'Rider',
            category: '40',
            checkpoint: 'Start',
            scannedBy: 'another',
          ),
          throwsA(
            isA<LocalDuplicateScanException>().having(
              (e) => e.confirmed,
              'confirmed',
              true,
            ),
          ),
        );
        expect(actions, ['scanCheckpoint', 'syncScans', 'syncScans']);
        expect(
          (await ScanHistoryService.entries()).single['scanned_at'],
          entry['scanned_at'],
        );
        await ScanHistoryService.record(
          riderId: '1',
          riderName: 'Rider',
          category: '40',
          checkpoint: 'Finish',
          scannedBy: '123',
        );
        await ScanHistoryService.record(
          riderId: '1',
          riderName: 'Rider',
          category: '100',
          checkpoint: 'Start',
          scannedBy: '123',
        );
        expect((await ScanHistoryService.entries()).length, 3);
      } finally {
        await ScanHistoryService.close();
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );
}
