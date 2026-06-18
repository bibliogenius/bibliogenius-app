import 'package:flutter/foundation.dart';
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
  late final MobileScannerController _controller;
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    // Start after the first frame, mirroring the working book scanner
    // (scan_screen.dart). Rendering MobileScanner directly (no isRunning-gate)
    // on the root navigator is what makes the macOS camera texture appear.
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
    if (_isProcessingScan) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      debugPrint(
        '📷 [SCAN] Barcode detected: ${raw.length > 80 ? '${raw.substring(0, 80)}...' : raw}',
      );

      final payload = parseScannedInvite(
        raw,
        onShortUrl: (shortUrl) {
          _isProcessingScan = true;
          setState(() {});
          _controller.stop();
          _handleShortInvite(shortUrl);
        },
      );
      if (payload != null) {
        _isProcessingScan = true;
        setState(() {});
        _controller.stop();
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
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'connection_failed'),
          ),
        ),
      );
      _isProcessingScan = false;
      setState(() {});
      _controller.start();
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
      if (kDebugMode)
        debugPrint(
          'QR Connect: connectPeer(hasKeys=${ed25519PublicKey != null}, hasRelay=${relayUrl != null})',
        );
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
      debugPrint(
        '📷 [CONNECT] Response: status=${response.statusCode}, data=${response.data}',
      );

      // connectLocalPeer returns error responses instead of throwing
      if (response.statusCode != null && response.statusCode! >= 400) {
        final rawMsg = response.data is Map
            ? response.data['error'] ?? 'Unknown error'
            : response.data?.toString() ?? 'Connection failed';
        final errorMsg = TranslationService.translate(context, rawMsg);
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
        _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Full-screen Stack with MobileScanner rendered directly (no isRunning-gate)
    // — the pattern that works on macOS. See scan_screen.dart / pairing scanner.
    final overlayColor = Theme.of(context).colorScheme.primary;
    return Stack(
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
        if (_isProcessingScan)
          const Center(
            child: CircularProgressIndicator(key: Key('scanProcessing')),
          ),
        Center(
          child: Container(
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
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Text(
            TranslationService.translate(context, 'scan_instruction'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
