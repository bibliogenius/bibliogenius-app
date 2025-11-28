import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isScanning = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() {
          _isScanning = false;
        });
        // Navigate to add book screen with ISBN
        context.push('/books/add', extra: {'isbn': barcode.rawValue});
        // Delay to prevent multiple scans
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ISBN')),
      body: MobileScanner(controller: controller, onDetect: _onDetect),
    );
  }
}
