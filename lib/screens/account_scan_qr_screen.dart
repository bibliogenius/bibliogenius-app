import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';

/// Generic QR scanner for the account-pairing flow. Returns the RAW scanned
/// string via `context.pop(value)` so the caller can hand it straight to the
/// validating FFI. Distinct from the peer-invite scanner (scan_qr_screen.dart),
/// which is hardwired to invite parsing and auto-connect.
///
/// Reuses the MobileScanner rendering recipe that works on macOS (autoStart
/// false, started after the first frame, rendered directly with no isRunning
/// gate). MUST be hosted on the root navigator (a top-level GoRoute), never
/// under the ShellRoute, or the macOS camera texture renders blank.
///
/// SECURITY (ADR-045): this screen is the authenticated channel. The codes it
/// reads (the new device's X25519 public key, the sealed trousseau) must only
/// ever be scanned in person, directly between the two devices. The caller
/// surfaces that warning; this screen only transports the scanned bytes.
class AccountScanQrScreen extends StatefulWidget {
  /// Title shown in the app bar.
  final String title;

  /// On-screen instruction under the viewfinder.
  final String instruction;

  /// Substring the payload must contain to be accepted (e.g. the wire type tag
  /// `"bg-pair"` or `"bg-sealed"`), so an unrelated QR (a peer invite, a book
  /// barcode) is ignored instead of returned. Authoritative validation still
  /// happens in Rust.
  final String expectedToken;

  const AccountScanQrScreen({
    super.key,
    required this.title,
    required this.instruction,
    required this.expectedToken,
  });

  @override
  State<AccountScanQrScreen> createState() => _AccountScanQrScreenState();
}

class _AccountScanQrScreenState extends State<AccountScanQrScreen> {
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
      if (!raw.contains(widget.expectedToken)) continue;
      _handled = true;
      _controller.stop();
      context.pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: GenieAppBar(title: widget.title),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      TranslationService.translate(context, 'camera_error'),
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
          Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: overlayColor.withValues(alpha: 0.6),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              width: 250,
              height: 250,
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Text(
              widget.instruction,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
