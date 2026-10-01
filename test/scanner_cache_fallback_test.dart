import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ride_track/models/rider.dart';
import 'package:ride_track/screens/scanner_screen.dart';
import 'package:ride_track/services/local_storage_service.dart';
import 'package:ride_track/services/rider_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.init();
  });

  tearDown(() {
    RiderService.riderDownloadError = null;
  });

  Future<void> search(WidgetTester tester, String id) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScannerScreen(
          checkpointName: 'Start',
          checkpointId: 'CP1',
          volunteerPhone: '123',
          volunteerName: 'Volunteer',
        ),
      ),
    );
    await tester.tap(find.text('Manual Check-in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), id);
    await tester.tap(find.text('SEARCH'));
    await tester.pumpAndSettle();
  }

  testWidgets('failed refresh without a cache still requires download', (
    tester,
  ) async {
    RiderService.riderDownloadError = 'Connection lost';
    await search(tester, '123');
    expect(find.text('Rider master unavailable'), findsOneWidget);
    expect(find.text('Confirm Rider'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Check-in').hitTestable(), findsOneWidget);
  });

  testWidgets('failed refresh uses saved rider and warns before submission', (
    tester,
  ) async {
    await LocalStorageService.saveRiderList(
      RiderList([
        const Rider(id: '123', name: 'Saved Rider', category: '40'),
      ], DateTime(2026, 9, 30, 10)),
    );
    RiderService.riderDownloadError = 'Connection lost';
    await search(tester, '123');
    expect(find.text('Confirm Rider'), findsOneWidget);
    expect(find.text('Saved Rider'), findsOneWidget);
    expect(
      find.textContaining('Refresh failed. Using rider list downloaded'),
      findsOneWidget,
    );
    expect(find.text('Rider master unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Check-in').hitTestable(), findsOneWidget);
  });

  testWidgets('unknown cached rider remains rejected after failed refresh', (
    tester,
  ) async {
    RiderService.riderDownloadError = 'Connection lost';
    await search(tester, '999');
    expect(
      find.textContaining('Rider not found in the downloaded list'),
      findsOneWidget,
    );
    expect(find.text('Confirm Rider'), findsNothing);
  });

  testWidgets('successful refresh has no fallback warning', (tester) async {
    await search(tester, '123');
    expect(find.text('Confirm Rider'), findsOneWidget);
    expect(find.textContaining('Refresh failed.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
