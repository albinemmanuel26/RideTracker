import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_track/screens/scanner_screen.dart';

void main() {
  testWidgets('scanner remains scrollable when keyboard reduces available height',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(
      home: ScannerScreen(
        checkpointName: 'Start', checkpointId: 'CP1',
        volunteerPhone: '123', volunteerName: 'Volunteer',
      ),
    ));
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Manual Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Check-in').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
