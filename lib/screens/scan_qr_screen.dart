import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';

class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'scan_qr_code'),
      ),
      body: const ScanContactView(),
    );
  }
}

/// View for Scanning Codes (extracted from original state)
class ScanContactView extends StatefulWidget {
  const ScanContactView({super.key});

  @override
  State<ScanContactView> createState() => _ScanContactViewState();
}

class _ScanContactViewState extends State<ScanContactView> {
  MobileScannerController cameraController = MobileScannerController(
    autoStart: false,
  );
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Start camera when view is visible
      if (mounted) {
        cameraController.start();
      }
    });
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  // Adapted from original _onDetect
  void _onDetect(BarcodeCapture capture) {
    if (_isProcessingScan) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        try {
          final data = jsonDecode(barcode.rawValue!);
          if (data['name'] != null && data['url'] != null) {
            // Stop the camera immediately to prevent further callbacks
            _isProcessingScan = true;
            cameraController.stop();
            setState(() {});
            // Call connect peer logic
            _connect(data['name'], data['url']);
            return;
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _connect(String name, String url) async {
    // Connect logic (simplified)
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.connectPeer(name, url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${TranslationService.translate(context, 'connected_to')} $name",
            ),
          ),
        );
        // Pop the screen on success
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${TranslationService.translate(context, 'connection_failed')}: $e",
            ),
          ),
        );
        // Restart camera to allow retrying
        _isProcessingScan = false;
        cameraController.start();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(controller: cameraController, onDetect: _onDetect),
              if (_isProcessingScan) const CircularProgressIndicator(),
              // Add a scanner overlay
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.red.withOpacity(0.5),
                    width: 4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                width: 250,
                height: 250,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            TranslationService.translate(context, 'scan_instruction'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
