import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';

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
/// [PairingScanResult]. Mirrors the camera lifecycle of the invite scanner
/// (delayed init + watchdog + explicit error/loading states) for reliability.
class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key});

  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  MobileScannerController? _controller;
  bool _isCameraReady = false;
  bool _handled = false;
  String? _cameraError;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    // Delay camera init so the screen renders first (prevents push freeze).
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _initCamera();
    });
  }

  void _initCamera() {
    try {
      _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.normal,
      );
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
      return;
    }
    _controller!.addListener(_onControllerStateChanged);
    _startCamera();
  }

  void _onControllerStateChanged() {
    final state = _controller?.value;
    if (state?.isRunning == true && !_isCameraReady) {
      _watchdog?.cancel();
      if (mounted) setState(() => _isCameraReady = true);
    }
  }

  void _startCamera() {
    if (!mounted || _controller == null) return;
    setState(() {
      _cameraError = null;
      _isCameraReady = false;
    });
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 10), () {
      if (mounted && !_isCameraReady && _cameraError == null) {
        setState(() => _cameraError = 'Camera initialization timed out');
      }
    });
    _controller!.start().then((_) => _watchdog?.cancel()).catchError((Object e) {
      _watchdog?.cancel();
      if (mounted) setState(() => _cameraError = e.toString());
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _controller?.removeListener(_onControllerStateChanged);
    _controller?.dispose();
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
        _controller?.stop();
        Navigator.of(context).pop(result);
        return;
      }
    }
    // A non-pairing QR was seen; keep scanning but hint once.
    if (!_handled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'pairing_error_qr_invalid'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'pairing_scan_button'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_cameraError != null) {
      return Center(
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    _controller != null ? _startCamera() : _initCamera(),
                icon: const Icon(Icons.refresh),
                label: Text(TranslationService.translate(context, 'retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady || _controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(TranslationService.translate(context, 'camera_loading')),
          ],
        ),
      );
    }

    final overlayColor = theme.colorScheme.primary;
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(controller: _controller!, onDetect: _onDetect),
              Container(
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            TranslationService.translate(context, 'pairing_scan_instruction'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
