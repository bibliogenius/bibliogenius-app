import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import '../services/translation_service.dart';
import '../utils/isbn_validator.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _isScanning = true;
  bool _isTorchOn = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  DateTime? _lastInvalidScanTime;

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    bool foundValid = false;

    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && IsbnValidator.isValid(rawValue)) {
        foundValid = true;
        // Valid ISBN found
        setState(() {
          _isScanning = false;
        });
        
        // Haptic feedback
        HapticFeedback.lightImpact();

        // Navigate to add book screen with ISBN
        context.push('/books/add', extra: {'isbn': rawValue});
        
        // Delay to prevent multiple scans if user comes back
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _isScanning = true;
            });
          }
        });
        return;
      }
    }

    // Feedback for invalid barcodes (debounced)
    if (!foundValid && barcodes.isNotEmpty) {
      final now = DateTime.now();
      if (_lastInvalidScanTime == null || 
          now.difference(_lastInvalidScanTime!) > const Duration(seconds: 2)) {
        _lastInvalidScanTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.translate(context, 'invalid_isbn_scanned') ?? 'Not a valid book barcode'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 280,
      height: 150,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'scan_isbn_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() {
                _isTorchOn = !_isTorchOn;
              });
              controller.toggleTorch();
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => controller.switchCamera(),
            tooltip: TranslationService.translate(context, 'switch_camera') ?? 'Switch Camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            // scanWindow removed to allow full screen detection
            errorBuilder: (context, error, child) {
              return Center(
                child: Text(
                  'Error: ${error.errorCode}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            },
          ),
          CustomPaint(
            painter: ScannerOverlayPainter(scanWindow),
            child: Container(),
          ),
          Positioned(
            bottom: 80,
            left: 20,
            right: 20,
            child: Text(
              TranslationService.translate(context, 'scan_instruction') ?? 'Align barcode within the frame',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 50,
            right: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.keyboard),
              label: Text(TranslationService.translate(context, 'btn_enter_manually') ?? 'Enter Manually'),
              onPressed: () {
                 context.push('/books/add');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  ScannerOverlayPainter(this.scanWindow);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)));

    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    // To create the hole, we need to use a layer composite or path difference.
    // Simpler approach for standard overlay:
    // Draw semi-transparent background everywhere EXCEPT the hole.
    
    // Actually, simple path operation:
    final backgroundWithHole = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(backgroundWithHole, Paint()..color = Colors.black54);

    // Draw border around the scan window
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)),
      borderPaint,
    );
    
    // Draw red line in center
    final linePaint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    canvas.drawLine(
      Offset(scanWindow.left + 20, scanWindow.center.dy),
      Offset(scanWindow.right - 20, scanWindow.center.dy),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
