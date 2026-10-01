import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ride_track/models/rider.dart';
import 'package:ride_track/screens/scanner_screen.dart';
import 'package:ride_track/services/local_storage_service.dart';
import 'package:ride_track/services/scan_history_service.dart';

void main() {
  testWidgets(
    'scan confirms local save and allows next rider without network',
    (tester) async {
      late Directory dir;
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        dir = await Directory.systemTemp.createTemp('scanner_local_save');
        await databaseFactory.setDatabasesPath(dir.path);
        await ScanHistoryService.database;
        SharedPreferences.setMockInitialValues({});
        await LocalStorageService.init();
        await LocalStorageService.saveRiderList(
          RiderList([
            const Rider(id: '123', name: 'Saved Rider', category: '40'),
          ], DateTime.now()),
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: ScannerScreen(
            checkpointName: 'Start',
            checkpointId: 'CP1',
            checkpointCategory: '40',
            volunteerPhone: '123',
            volunteerName: 'Volunteer',
          ),
        ),
      );
      await tester.tap(find.text('Manual Check-in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('SEARCH'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      // Pump UI continuations between real SQLite callbacks.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Saved locally').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.text('Saved locally'), findsOneWidget);
      expect(
        find.textContaining('Upload queued automatically'),
        findsOneWidget,
      );
      expect(find.textContaining('1 pending'), findsOneWidget);
      await tester.tap(find.text('DISMISS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual Check-in'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        expect((await ScanHistoryService.entries()).single['confirmed'], false);
        await ScanHistoryService.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
