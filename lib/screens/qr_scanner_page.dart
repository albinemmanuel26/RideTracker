import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/app_constants.dart';

enum QRScannerAction { manualEntry }

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  // The device has one camera session, including during route transitions.
  static Future<void>? _cameraWork;

  static void _chainCameraWork(Future<void> Function() operation) {
    final work = (_cameraWork ?? Future<void>.value()).then((_) => operation());
    _cameraWork = work;
    work.then((_) {
      if (identical(_cameraWork, work)) _cameraWork = null;
    });
  }

  bool _detected = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _busy = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    // MobileScanner must attach the controller before the first start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCamera();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Permission prompts may still be completing. Dispose only after any
    // outstanding camera operation, never concurrently with start/stop.
    _chainCameraWork(() async {
      try {
        await _controller.dispose();
      } catch (error) {
        debugPrint('Camera cleanup failed: $error');
      }
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // Permission dialogs change lifecycle while start is pending. Its completion
    // handles the latest state, avoiding another permission request on dismissal.
    if (!_controller.value.isStarting) _syncCamera();
  }

  void _enqueue(Future<void> Function() operation) {
    _chainCameraWork(() async {
      if (_disposed) return;
      setState(() => _busy = true);
      try {
        await operation();
      } catch (error) {
        _showCameraError(error);
      } finally {
        if (mounted && !_disposed) setState(() => _busy = false);
      }
    });
  }

  void _syncCamera({bool restart = false}) {
    _enqueue(() async {
      // Read the latest lifecycle state, discarding stale queued transitions.
      if (!_foreground ||
          _detected ||
          ModalRoute.of(context)?.isCurrent == false) {
        await _controller.stop();
        return;
      }
      if (restart) await _controller.stop();
      if (_disposed || !_foreground || _detected) return;
      await _controller.start();
      if (!_disposed && (!_foreground || _detected)) await _controller.stop();
      if (mounted && !_disposed) {
        setState(() {
          final error = _controller.value.error;
          _cameraError = error == null ? null : _errorMessage(error);
        });
      }
    });
  }

  String _errorMessage(Object error) {
    if (error is MobileScannerException) {
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        return 'Camera permission is off. Enable camera access for Ride Track '
            'in your phone settings, then return and retry. You can also enter the rider ID manually.';
      }
      if (error.errorCode == MobileScannerErrorCode.unsupported) {
        return 'No supported camera is available. Please use manual entry.';
      }
    }
    return 'The camera could not scan. Retry the camera or enter the rider ID manually.';
  }

  void _showCameraError(Object error) {
    if (mounted && !_disposed && !_detected) {
      setState(() => _cameraError = _errorMessage(error));
    }
  }

  void _finish(Object result) {
    if (!mounted || _disposed || _detected) return;
    _detected = true;
    _syncCamera();
    Navigator.of(context).pop(result);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected ||
        !_foreground ||
        _disposed ||
        _cameraError != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    // Preserve the raw value and let the existing rider flow validate it.
    _finish(value);
  }

  void _toggleTorch() {
    _enqueue(() async {
      if (!_foreground || _detected || !_controller.value.isRunning) return;
      try {
        await _controller.toggleTorch();
      } catch (_) {
        if (mounted && !_disposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Flashlight unavailable. You can keep scanning.'),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan QR Code',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: _controller,
        builder: (context, state, _) {
          final message =
              _cameraError ??
              (state.error == null ? null : _errorMessage(state.error!));
          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                useAppLifecycleState: false,
                onDetect: _onDetect,
                onDetectError: (error, _) => _showCameraError(error),
                errorBuilder: (_, _) => const SizedBox.expand(),
              ),
              if (message == null)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanOverlayPainter(),
                    child: const SizedBox.expand(),
                  ),
                )
              else
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              _buildBottomBar(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(MobileScannerState state) {
    final isOn = state.torchState == TorchState.on;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _busy
                            ? 'Preparing camera…'
                            : "Point camera at rider's QR code",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isOn ? Icons.flash_on : Icons.flash_off,
                        color: isOn
                            ? AppConstants.secondaryColor
                            : Colors.white54,
                      ),
                      tooltip: isOn
                          ? 'Turn off flashlight'
                          : 'Turn on flashlight',
                      onPressed:
                          _busy ||
                              !state.isRunning ||
                              state.torchState == TorchState.unavailable
                          ? null
                          : _toggleTorch,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _busy || !_foreground || _detected
                            ? null
                            : () => _syncCamera(restart: true),
                        child: const Text('Retry camera'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _detected
                            ? null
                            : () => _finish(QRScannerAction.manualEntry),
                        child: const Text('Manual entry'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan window overlay
// ---------------------------------------------------------------------------

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanSize = size.width * 0.68;
    final double left = (size.width - scanSize) / 2;
    final double top = (size.height - scanSize) / 2 - 40;
    final Rect scanRect = Rect.fromLTWH(left, top, scanSize, scanSize);

    // Dim everything outside the scan window
    final Paint dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55);
    final Path dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, dimPaint);

    // Corner brackets
    const double cornerLen = 28;
    const double strokeW = 3.5;
    const double r = 14;
    final Paint corner = Paint()
      ..color = AppConstants.primaryColor
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const double pi = 3.14159;

    // Top-left
    canvas.drawLine(
      Offset(left + r, top),
      Offset(left + cornerLen, top),
      corner,
    );
    canvas.drawLine(
      Offset(left, top + r),
      Offset(left, top + cornerLen),
      corner,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top, r * 2, r * 2),
      pi,
      0.5 * pi,
      false,
      corner,
    );

    // Top-right
    canvas.drawLine(
      Offset(left + scanSize - cornerLen, top),
      Offset(left + scanSize - r, top),
      corner,
    );
    canvas.drawLine(
      Offset(left + scanSize, top + r),
      Offset(left + scanSize, top + cornerLen),
      corner,
    );
    canvas.drawArc(
      Rect.fromLTWH(left + scanSize - r * 2, top, r * 2, r * 2),
      -0.5 * pi,
      0.5 * pi,
      false,
      corner,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(left + r, top + scanSize),
      Offset(left + cornerLen, top + scanSize),
      corner,
    );
    canvas.drawLine(
      Offset(left, top + scanSize - cornerLen),
      Offset(left, top + scanSize - r),
      corner,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top + scanSize - r * 2, r * 2, r * 2),
      0.5 * pi,
      0.5 * pi,
      false,
      corner,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(left + scanSize - cornerLen, top + scanSize),
      Offset(left + scanSize - r, top + scanSize),
      corner,
    );
    canvas.drawLine(
      Offset(left + scanSize, top + scanSize - cornerLen),
      Offset(left + scanSize, top + scanSize - r),
      corner,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        left + scanSize - r * 2,
        top + scanSize - r * 2,
        r * 2,
        r * 2,
      ),
      0,
      0.5 * pi,
      false,
      corner,
    );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter oldDelegate) => false;
}
