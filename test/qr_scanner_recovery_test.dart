import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ride_track/screens/qr_scanner_page.dart';
import 'package:ride_track/screens/scanner_screen.dart';

class CameraPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final events = <String>[];
  Completer<void>? startGate;
  Completer<void>? stopGate;
  Object? startError;
  Object? stopError;
  bool torchFails = false;
  int active = 0;
  int maxActive = 0;

  Future<void> operation(
    String name,
    Completer<void>? gate,
    Object? error,
  ) async {
    events.add(name);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (gate != null) await gate.future;
      if (error != null) throw error;
    } finally {
      active--;
    }
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    expectSync(options.cameraDirection, CameraFacing.back);
    expectSync(options.detectionSpeed, DetectionSpeed.noDuplicates);
    await operation('start', startGate, startError);
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() => operation('stop', stopGate, stopError);
  @override
  Future<void> dispose() => operation('dispose', null, null);
  @override
  Future<void> toggleTorch() =>
      operation('torch', null, torchFails ? StateError('No torch') : null);
}

void main() {
  late CameraPlatform camera;
  late MobileScannerPlatform previous;
  setUp(() {
    previous = MobileScannerPlatform.instance;
    camera = CameraPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = previous;
    MobileScannerController.resetPlatformSessionOwner();
  });
  Future<void> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(home: QRScannerPage()));
    await tester.pumpAndSettle();
  }

  Future<void> remove(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permission prompt lifecycle changes do not overlap camera starts',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester);
      expect(camera.events, ['start']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.events, ['start']);
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.events, ['start']);
      expect(camera.maxActive, 1);
      camera.stopGate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.events, ['start', 'stop']);
      camera.stopGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.events, ['start', 'stop', 'start']);
      expect(camera.maxActive, 1);
      await remove(tester);
    },
  );

  testWidgets(
    'denying the permission prompt does not immediately request again',
    (tester) async {
      camera.startGate = Completer<void>();
      camera.startError = const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.events, ['start']);
      expect(find.textContaining('Camera permission is off'), findsOneWidget);
      await remove(tester);
    },
  );

  testWidgets(
    'backgrounding during startup stops camera once startup completes',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.events, ['start', 'stop']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.events, ['start', 'stop', 'start']);
      expect(camera.maxActive, 1);
      await remove(tester);
    },
  );

  testWidgets('permission denial shows recovery and retry starts camera', (
    tester,
  ) async {
    camera.startError = const MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    );
    await open(tester);
    expect(find.textContaining('Camera permission is off'), findsOneWidget);
    expect(find.text('Manual entry'), findsOneWidget);
    camera.startError = null;
    await tester.tap(find.text('Retry camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera permission is off'), findsNothing);
    expect(camera.events.where((e) => e == 'start').length, 2);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets(
    'stop and barcode stream errors offer recovery without uncaught errors',
    (tester) async {
      await open(tester);
      camera.stopError = StateError('Camera interrupted');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.textContaining('The camera could not scan'), findsOneWidget);
      camera.stopError = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('The camera could not scan'), findsNothing);
      camera.captures.addError(StateError('Capture failed'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The camera could not scan'), findsOneWidget);
      await tester.tap(find.text('Retry camera'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The camera could not scan'), findsNothing);
      expect(tester.takeException(), isNull);
      await remove(tester);
    },
  );

  testWidgets('disposing during camera startup waits for startup completion', (
    tester,
  ) async {
    camera.startGate = Completer<void>();
    await open(tester);
    await remove(tester);
    expect(camera.events, ['start']);
    await open(tester); // A new scanner must wait for the old camera cleanup.
    expect(camera.events, ['start']);
    camera.startGate!.complete();
    await tester.pumpAndSettle();
    expect(camera.events, ['start', 'dispose', 'start']);
    expect(camera.maxActive, 1);
    expect(tester.takeException(), isNull);
    expect(camera.events.last, 'start');
    await remove(tester);
  });

  testWidgets('flashlight errors do not block QR scanning', (tester) async {
    await open(tester);
    camera.torchFails = true;
    await tester.tap(find.byTooltip('Turn on flashlight'));
    await tester.pumpAndSettle();
    expect(
      find.text('Flashlight unavailable. You can keep scanning.'),
      findsOneWidget,
    );
    expect(find.textContaining('The camera could not scan'), findsNothing);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets('camera recovery opens the existing manual check-in dialog', (
    tester,
  ) async {
    camera.startError = const MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
    await tester.tap(find.text('SCAN QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual entry'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('Scan QR Code'), findsNothing);
    await remove(tester);
  });

  testWidgets('QR value returns unchanged only once and scanner can reopen', (
    tester,
  ) async {
    var results = 0;
    Object? value;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                value = await Navigator.of(context).push<Object>(
                  MaterialPageRoute(builder: (_) => const QRScannerPage()),
                );
                results++;
              },
              child: const Text('Open scanner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    const raw = '{"rider_id":"123"}';
    final capture = BarcodeCapture(barcodes: [const Barcode(rawValue: raw)]);
    camera.captures.add(capture);
    camera.captures.add(capture);
    await tester.pumpAndSettle();
    expect(value, raw);
    expect(results, 1);
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });
}
