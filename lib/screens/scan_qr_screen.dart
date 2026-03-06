import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/flash_message_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../utils/invite_payload.dart';
import '../widgets/genie_app_bar.dart';

class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('📷 [SCREEN] ScanQrScreen.build()');
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'scan_qr_code'),
      ),
      body: const ScanContactView(),
    );
  }
}

/// View for Scanning Codes
class ScanContactView extends StatefulWidget {
  const ScanContactView({super.key});

  @override
  State<ScanContactView> createState() => _ScanContactViewState();
}

class _ScanContactViewState extends State<ScanContactView> {
  MobileScannerController? _controller;
  bool _isProcessingScan = false;
  bool _isCameraReady = false;
  String? _cameraError;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    debugPrint('📷 [INIT] ScanContactView.initState() — platform=${Platform.operatingSystem}');
    // Delay camera init so the screen renders first (prevents freeze on push)
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('📷 [INIT] Delayed init callback fired');
      if (mounted) _initCamera();
    });
  }

  void _initCamera() {
    debugPrint('📷 [CAM] _initCamera() — creating MobileScannerController...');
    final stopwatch = Stopwatch()..start();
    try {
      _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.normal,
      );
      stopwatch.stop();
      debugPrint('📷 [CAM] Controller created OK in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stack) {
      stopwatch.stop();
      debugPrint('📷 [CAM] Controller creation FAILED in ${stopwatch.elapsedMilliseconds}ms: $e');
      debugPrint('📷 [CAM] Stack: $stack');
      if (mounted) {
        setState(() => _cameraError = 'Camera init failed: $e');
      }
      return;
    }

    // Listen for controller state changes
    _controller!.addListener(_onControllerStateChanged);
    _startCamera();
  }

  void _onControllerStateChanged() {
    final state = _controller?.value;
    debugPrint('📷 [STATE] Controller state changed: isInitialized=${state?.isInitialized}, isRunning=${state?.isRunning}');
    if (state?.isRunning == true && !_isCameraReady) {
      debugPrint('📷 [STATE] Camera IS RUNNING — showing preview');
      _watchdog?.cancel();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    }
  }

  void _startCamera() {
    if (!mounted || _controller == null) return;
    debugPrint('📷 [CAM] _startCamera() — calling controller.start()...');
    setState(() {
      _cameraError = null;
      _isCameraReady = false;
    });

    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 10), () {
      debugPrint('📷 [CAM] ⏰ WATCHDOG FIRED — camera did not start within 10s');
      if (mounted && !_isCameraReady && _cameraError == null) {
        setState(() {
          _cameraError = 'Camera initialization timed out after 10s';
        });
      }
    });

    final stopwatch = Stopwatch()..start();

    // Fire-and-forget — do NOT await
    _controller!.start().then((_) {
      stopwatch.stop();
      _watchdog?.cancel();
      debugPrint('📷 [CAM] ✅ start() resolved OK in ${stopwatch.elapsedMilliseconds}ms');
    }).catchError((e) {
      stopwatch.stop();
      _watchdog?.cancel();
      debugPrint('📷 [CAM] ❌ start() FAILED in ${stopwatch.elapsedMilliseconds}ms: $e');
      if (mounted) {
        setState(() => _cameraError = e.toString());
      }
    });

    debugPrint('📷 [CAM] start() dispatched (fire-and-forget), waiting...');
  }

  @override
  void dispose() {
    debugPrint('📷 [DISPOSE] ScanContactView.dispose()');
    _watchdog?.cancel();
    _controller?.removeListener(_onControllerStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessingScan) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      debugPrint('📷 [SCAN] Barcode detected: ${raw.length > 80 ? '${raw.substring(0, 80)}...' : raw}');

      final payload = parseScannedInvite(
        raw,
        onShortUrl: (shortUrl) {
          _isProcessingScan = true;
          setState(() {});
          _controller?.stop();
          _handleShortInvite(shortUrl);
        },
      );
      if (payload != null) {
        _isProcessingScan = true;
        setState(() {});
        _controller?.stop();
        _connectFromPayload(payload);
        return;
      }
      // If onShortUrl was triggered, _isProcessingScan is already true
      if (_isProcessingScan) return;
    }
  }

  Future<void> _handleShortInvite(String shortUrl) async {
    final payload = await resolveShortInvite(shortUrl);
    if (!mounted) return;
    if (payload != null) {
      _connectFromPayload(payload);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          TranslationService.translate(context, 'connection_failed'),
        )),
      );
      _isProcessingScan = false;
      setState(() {});
      _startCamera();
    }
  }

  void _connectFromPayload(Map<String, dynamic> data) {
    _connect(
      data['name'] as String,
      data['url'] as String? ?? '',
      libraryUuid: data['library_uuid'] as String?,
      ed25519PublicKey: data['ed25519_public_key'] as String?,
      x25519PublicKey: data['x25519_public_key'] as String?,
      relayUrl: data['relay_url'] as String?,
      mailboxId: data['mailbox_id'] as String?,
      relayWriteToken: data['relay_write_token'] as String?,
    );
  }

  Future<void> _connect(
    String name,
    String url, {
    String? libraryUuid,
    String? ed25519PublicKey,
    String? x25519PublicKey,
    String? relayUrl,
    String? mailboxId,
    String? relayWriteToken,
  }) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      debugPrint('QR Connect: connectPeer($name, $url, hasKeys=${ed25519PublicKey != null}, hasRelay=${relayUrl != null})');
      final response = await api.connectPeer(
        name,
        url,
        libraryUuid: libraryUuid,
        ed25519PublicKey: ed25519PublicKey,
        x25519PublicKey: x25519PublicKey,
        relayUrl: relayUrl,
        mailboxId: mailboxId,
        relayWriteToken: relayWriteToken,
      );
      debugPrint('📷 [CONNECT] Response: status=${response.statusCode}, data=${response.data}');

      // connectLocalPeer returns error responses instead of throwing
      if (response.statusCode != null && response.statusCode! >= 400) {
        final errorMsg = response.data is Map
            ? response.data['error'] ?? 'Unknown error'
            : response.data?.toString() ?? 'Connection failed';
        throw Exception(errorMsg);
      }

      if (mounted) {
        context.read<FlashMessageProvider>().addEphemeralPeer(
          EphemeralPeerFlash(
            peerId: url.hashCode & 0x7FFFFFFF,
            peerName: name,
            peerUrl: url,
            hasRelayCredentials: relayUrl != null && mailboxId != null,
            connectedAt: DateTime.now(),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      debugPrint('📷 [CONNECT] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${TranslationService.translate(context, 'connection_failed')}: $e",
            ),
          ),
        );
        _isProcessingScan = false;
        setState(() {});
        _startCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('📷 [BUILD] error=${_cameraError != null}, ready=$_isCameraReady, controller=${_controller != null}');

    // --- Error state ---
    if (_cameraError != null) {
      return Center(
        key: const Key('cameraErrorState'),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
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
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('cameraRetryBtn'),
                onPressed: () {
                  if (_controller != null) {
                    _startCamera();
                  } else {
                    _initCamera();
                  }
                },
                icon: const Icon(Icons.refresh),
                label: Text(
                  TranslationService.translate(context, 'retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // --- Loading state: controller not created yet, or camera not running ---
    if (!_isCameraReady || _controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(context, 'camera_loading'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    // --- Camera preview (only when confirmed running) ---
    final overlayColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: _controller!,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) {
                  debugPrint('📷 [WIDGET] MobileScanner errorBuilder: ${error.errorCode}');
                  _watchdog?.cancel();
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
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Error: ${error.errorCode.name}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_isProcessingScan)
                const CircularProgressIndicator(
                  key: Key('scanProcessing'),
                ),
              Container(
                key: const Key('scannerOverlay'),
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
