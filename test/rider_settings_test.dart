import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ride_track/models/rider.dart';
import 'package:ride_track/services/local_storage_service.dart';
import 'package:ride_track/screens/scanner_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.init();
  });
  testWidgets(
    'manual lookup uses local riders and settings contains refresh and checkpoint',
    (tester) async {
      await LocalStorageService.saveRiderList(
        RiderList([
          const Rider(id: '123', name: 'Local Rider', category: '40'),
        ], DateTime(2026, 9, 30, 10, 15)),
      );
      await LocalStorageService.saveSession(
        volunteerPhone: '1',
        volunteerName: 'Volunteer',
        volunteerRole: 'scanner',
        checkpointId: 'CP1',
        checkpointName: 'Start',
        checkpointCategory: '40',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ScannerScreen(
            checkpointName: 'Start',
            checkpointId: 'CP1',
            checkpointCategory: '40',
            volunteerPhone: '1',
            volunteerName: 'Volunteer',
          ),
        ),
      );
      expect(find.byTooltip('Change Checkpoint'), findsNothing);
      await tester.tap(find.text('Manual Check-in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('SEARCH'));
      await tester.pumpAndSettle();
      // Widget tests prohibit real HTTP: this confirmation must come from cache.
      expect(find.text('Local Rider'), findsOneWidget);
      expect(find.text('Confirm Rider'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Refresh rider list'), findsOneWidget);
      expect(find.textContaining('Last updated:'), findsOneWidget);
      expect(find.text('Change Checkpoint'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
