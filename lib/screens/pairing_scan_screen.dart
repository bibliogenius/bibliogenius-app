import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/translation_service.dart';

/// Result of scanning a `bibliogenius://pair` QR code: the 6-digit code and the
/// offerer's reachable LAN URL (so the acceptor skips mDNS / stale-IP guesswork).
class PairingScanResult {
  final String code;
  final String url;
  const PairingScanResult(this.code, this.url);

  /// Parse a scanned string. Returns null if it is not a pairing QR.
  static PairingScanResult? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'bibliogenius' || uri.host != 'pair') {
      return null;
    }
    final code = uri.queryParameters['code'];
    final url = uri.queryParameters['url'];
    if (code == null || code.length != 6 || url == null || url.isEmpty) {
      return null;
    }
    return PairingScanResult(code, url);
  }
}

/// Camera screen that scans a BiblioGenius pairing QR and pops with a
/// [PairingScanResult].
///
/// Mirrors the working book-ISBN scanner (`scan_screen.dart`): the
/// [MobileScanner] widget is rendered directly and `start()` is called from a
/// post-frame callback. We deliberately do NOT gate the preview behind an
/// `isRunning` listener — that listener is unreliable on macOS and leaves the
/// UI stuck on a spinner, which is exactly what the previous version did.
class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key});

  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    // Start after the first frame so the screen renders before the camera
    // spins up (avoids immediate permission-denial errors on some platforms).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final result = PairingScanResult.tryParse(raw);
      if (result != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(result);
        return;
      }
    }
    // Non-pairing QR codes are ignored; keep scanning.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'pairing_scan_button'),
        ),
      ),
      // Full-screen Stack with MobileScanner as the first child, matching the
      // working book scanner. Wrapping it in Column>Expanded made the macOS
      // camera texture render blank.
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      TranslationService.translate(context, 'camera_error'),
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              width: 250,
              height: 250,
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Text(
              TranslationService.translate(context, 'pairing_scan_instruction'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
