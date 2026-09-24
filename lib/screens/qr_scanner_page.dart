import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/app_constants.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller.stop();
        break;
      default:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _detected = true;
    _controller.stop();
    // Return the raw QR value to the caller
    Navigator.of(context).pop(value);
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
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          CustomPaint(
            painter: _ScanOverlayPainter(),
            child: const SizedBox.expand(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                "Point camera at rider's QR code",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                final isOn = state.torchState == TorchState.on;
                return IconButton(
                  icon: Icon(
                    isOn ? Icons.flash_on : Icons.flash_off,
                    color: isOn
                        ? AppConstants.secondaryColor
                        : Colors.white54,
                  ),
                  tooltip: isOn ? 'Turn off flashlight' : 'Turn on flashlight',
                  onPressed: _controller.toggleTorch,
                );
              },
            ),
          ],
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
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
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
    canvas.drawLine(Offset(left + r, top), Offset(left + cornerLen, top), corner);
    canvas.drawLine(Offset(left, top + r), Offset(left, top + cornerLen), corner);
    canvas.drawArc(Rect.fromLTWH(left, top, r * 2, r * 2), pi, 0.5 * pi, false, corner);

    // Top-right
    canvas.drawLine(Offset(left + scanSize - cornerLen, top), Offset(left + scanSize - r, top), corner);
    canvas.drawLine(Offset(left + scanSize, top + r), Offset(left + scanSize, top + cornerLen), corner);
    canvas.drawArc(Rect.fromLTWH(left + scanSize - r * 2, top, r * 2, r * 2), -0.5 * pi, 0.5 * pi, false, corner);

    // Bottom-left
    canvas.drawLine(Offset(left + r, top + scanSize), Offset(left + cornerLen, top + scanSize), corner);
    canvas.drawLine(Offset(left, top + scanSize - cornerLen), Offset(left, top + scanSize - r), corner);
    canvas.drawArc(Rect.fromLTWH(left, top + scanSize - r * 2, r * 2, r * 2), 0.5 * pi, 0.5 * pi, false, corner);

    // Bottom-right
    canvas.drawLine(Offset(left + scanSize - cornerLen, top + scanSize), Offset(left + scanSize - r, top + scanSize), corner);
    canvas.drawLine(Offset(left + scanSize, top + scanSize - cornerLen), Offset(left + scanSize, top + scanSize - r), corner);
    canvas.drawArc(Rect.fromLTWH(left + scanSize - r * 2, top + scanSize - r * 2, r * 2, r * 2), 0, 0.5 * pi, false, corner);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter oldDelegate) => false;
}
