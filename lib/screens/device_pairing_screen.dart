import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers/device_sync_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mdns_service.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../theme/app_design.dart';
import 'pairing_scan_screen.dart';

enum _PairingView { devices, showCode, enterCode }

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  _PairingView _view = _PairingView.devices;

  // Device list
  List<frb.FrbLinkedDevice> _devices = [];
  bool _isLoadingDevices = true;

  // Code generation
  String? _generatedCode;
  bool _isGenerating = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 300;

  // Code entry
  final _codeController = TextEditingController();
  bool _isPairing = false;

  // mDNS peers for target selection
  List<DiscoveredPeer> _localPeers = [];
  DiscoveredPeer? _selectedPeer;

  // This node's own LAN URL, embedded in the pairing QR (offerer side).
  String? _pairingUrl;

  // URL captured by scanning a pairing QR (acceptor side); when set it takes
  // priority over the mDNS-selected peer and carries a guaranteed-fresh address.
  String? _scannedPeerUrl;

  // Auto-refresh timer
  Timer? _refreshTimer;
  StreamSubscription<frb.FrbNudgeEvent>? _nudgeSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _ensureMdnsDiscovery();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _view == _PairingView.devices) {
        _loadDevices(silent: true);
      }
    });
    // Instant refresh on relay nudge (ADR-017)
    _subscribeNudgeStream();
  }

  /// Subscribe to the FFI relay nudge stream for instant device list refresh.
  void _subscribeNudgeStream() {
    _nudgeSub?.cancel();
    try {
      _nudgeSub = frb.subscribeRelayNudges().listen(
        (_) {
          if (mounted && _view == _PairingView.devices) {
            _loadDevices(silent: true);
          }
        },
        onError: (Object e) {
          debugPrint('DevicePairing: nudge stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('DevicePairing: failed to subscribe to nudge stream: $e');
    }
  }

  /// Ensure mDNS discovery is running so we can resolve peer URLs for sync.
  Future<void> _ensureMdnsDiscovery() async {
    if (!MdnsService.isActive) {
      await MdnsService.startDiscovery();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    _nudgeSub?.cancel();
    _codeController.dispose();
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  bool _backfillDone = false;

  Future<void> _loadDevices({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingDevices = true);
    try {
      final devices = await frb.deviceListLinked();
      // Backfill operation_log once if there are linked devices
      if (!_backfillDone && devices.isNotEmpty) {
        _backfillDone = true;
        final count = await frb.deviceSyncBackfill();
        if (count > 0) {
          debugPrint('DevicePairing: backfilled $count operations');
        }
      }
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoadingDevices = false;
        });
        // Refresh pending review count for badge display
        context.read<DeviceSyncProvider>().loadPendingReview();
      }
    } catch (e) {
      debugPrint('DevicePairing: loadDevices error: $e');
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
    }
  }

  Future<void> _generateCode() async {
    setState(() {
      _isGenerating = true;
      _view = _PairingView.showCode;
    });
    try {
      final authService = context.read<AuthService>();
      final apiService = context.read<ApiService>();
      final libraryUuid = await authService.getOrCreateLibraryUuid();
      final deviceName = _pairingDeviceName();

      // Our LAN URL to embed in the QR so the acceptor reaches us directly.
      final myUrl = await apiService.getMyLanUrl();

      final offer = await frb.deviceGeneratePairingOffer(
        deviceName: deviceName,
        libraryUuid: libraryUuid,
      );

      if (mounted) {
        setState(() {
          _generatedCode = offer.code;
          _pairingUrl = myUrl;
          _isGenerating = false;
          _remainingSeconds = 300;
        });
        _enableWakelock();
        _startCountdown();
      }
    } catch (e) {
      debugPrint('DevicePairing: generateCode error: $e');
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _view = _PairingView.devices;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_error'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _releaseWakelock();
        if (mounted) {
          setState(() {
            _generatedCode = null;
            _view = _PairingView.devices;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'pairing_code_expired'),
              ),
            ),
          );
        }
      }
    });
  }

  bool _isScanning = false;

  Future<void> _loadLocalPeers() async {
    setState(() => _isScanning = true);
    // Always restart discovery to get fresh peers (stale cache is common)
    await MdnsService.startDiscovery();
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final peers = MdnsService.peers;
    setState(() {
      _localPeers = peers;
      _selectedPeer = null;
      _isScanning = false;
    });
  }

  String? _getPeerUrl(DiscoveredPeer peer) {
    final ip = peer.addresses.isNotEmpty ? peer.addresses.first : peer.host;
    if (ip.isEmpty) return null;
    return 'http://$ip:${peer.port}';
  }

  /// The URL to POST the pairing code to: a scanned QR address wins (fresh,
  /// no mDNS guesswork), otherwise the manually selected mDNS peer.
  String? _resolveAcceptUrl() {
    if (_scannedPeerUrl != null) return _scannedPeerUrl;
    final peer = _selectedPeer;
    return peer == null ? null : _getPeerUrl(peer);
  }

  /// Open the camera to scan a pairing QR, then auto-fill the code + target URL
  /// and pair immediately — skipping manual code entry and peer selection.
  Future<void> _scanPairingQr() async {
    // Push on the ROOT navigator: mobile_scanner's macOS camera texture renders
    // blank inside the shell's nested navigator (the nav sidebar stays visible).
    // The book scanner works precisely because it opens full-screen on root.
    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<PairingScanResult>(
      MaterialPageRoute(builder: (_) => const PairingScanScreen()),
    );
    if (!mounted || result == null) return;
    setState(() {
      _scannedPeerUrl = result.url;
      _codeController.text = result.code;
    });
    await _acceptCode();
  }

  Future<void> _acceptCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    final peerUrl = _resolveAcceptUrl();
    if (peerUrl == null) return;

    setState(() => _isPairing = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Pre-flight: a peer whose app is backgrounded accepts the TCP socket but
    // never answers (iOS suspends the process), so a blind POST hangs ~10s and
    // then surfaces a cryptic error. Probe first and fail fast with guidance.
    final reachable = await apiService.checkPeerConnectivity(peerUrl);
    if (!mounted) return;
    if (!reachable) {
      setState(() => _isPairing = false);
      _showPairingError(PairingErrorKind.unreachable);
      return;
    }

    try {
      final deviceName = _pairingDeviceName();

      // Fetch our crypto keys for E2EE exchange (keys are hex-encoded)
      Uint8List ed25519Bytes = Uint8List(0);
      Uint8List x25519Bytes = Uint8List(0);
      try {
        final keysJson = await frb.getPublicKeysFfi();
        final keys = Map<String, dynamic>.from(
          const JsonDecoder().convert(keysJson) as Map,
        );
        final ed25519 = keys['ed25519'] as String?;
        final x25519 = keys['x25519'] as String?;
        if (ed25519 != null) ed25519Bytes = _hexDecode(ed25519);
        if (x25519 != null) x25519Bytes = _hexDecode(x25519);
      } catch (e) {
        debugPrint('DevicePairing: Could not fetch crypto keys: $e');
      }

      debugPrint(
        'DevicePairing: acceptCode ed25519=${ed25519Bytes.length}B x25519=${x25519Bytes.length}B device=$deviceName',
      );
      if (ed25519Bytes.isEmpty || x25519Bytes.isEmpty) {
        debugPrint(
          'DevicePairing: WARNING - empty crypto keys, pairing will be incomplete',
        );
      }

      // Send code to the remote peer's HTTP server
      final pairingResponse = await apiService.sendPairingCode(
        peerUrl: peerUrl,
        code: code,
        deviceName: deviceName,
        ed25519PublicKey: ed25519Bytes.toList(),
        x25519PublicKey: x25519Bytes.toList(),
      );

      // Register the offerer (the device that generated the code) locally
      // so that sync works bidirectionally.
      try {
        final offererEd25519 = pairingResponse['offerer_ed25519'];
        final offererX25519 = pairingResponse['offerer_x25519'];
        final offererName = _selectedPeer?.name ?? 'Unknown Device';

        if (offererEd25519 is List && offererX25519 is List) {
          final dio = Dio(
            BaseOptions(
              baseUrl: 'http://127.0.0.1:${ApiService.httpPort}',
              connectTimeout: const Duration(seconds: 5),
            ),
          );
          await dio.post(
            '/api/devices/register',
            data: {
              'name': offererName,
              'ed25519_public_key': offererEd25519,
              'x25519_public_key': offererX25519,
            },
          );
          debugPrint(
            'DevicePairing: registered offerer "$offererName" as linked device',
          );
        } else {
          debugPrint(
            'DevicePairing: WARNING - offerer keys missing from pairing response',
          );
        }
      } catch (e) {
        debugPrint('DevicePairing: failed to register offerer: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_success'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _codeController.clear();
        setState(() {
          _isPairing = false;
          _selectedPeer = null;
          _scannedPeerUrl = null;
          _view = _PairingView.devices;
        });
        _loadDevices();
      }
    } catch (e) {
      debugPrint('DevicePairing: acceptCode error: $e');
      if (mounted) {
        setState(() => _isPairing = false);
        final kind = e is PairingException
            ? e.kind
            : PairingErrorKind.unknown;
        _showPairingError(kind);
      }
    }
  }

  /// Show a precise, translated pairing error (never a raw exception).
  void _showPairingError(PairingErrorKind kind) {
    if (!mounted) return;
    final key = switch (kind) {
      PairingErrorKind.unreachable => 'pairing_error_unreachable',
      PairingErrorKind.expired => 'pairing_error_expired',
      PairingErrorKind.invalid => 'pairing_error_invalid',
      PairingErrorKind.rateLimited => 'pairing_error_rate_limited',
      PairingErrorKind.registrationFailed => 'pairing_error_registration',
      PairingErrorKind.unknown => 'pairing_error',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(TranslationService.translate(context, key)),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Try to find the mDNS LAN URL for a linked device.
  /// Prefers a stable identity match on the ed25519 public key, then falls
  /// back to name matching (hostname, library name, partial).
  String? _findPeerUrl(frb.FrbLinkedDevice device) {
    final peers = MdnsService.peers;

    // Identity match first: the ed25519 public key is stable and immune to
    // display-name drift (e.g. a device stored as "localhost" because iOS
    // reports that as Platform.localHostname). mDNS advertises the peer's
    // ed25519 as hex; compare against the linked device's key bytes.
    if (device.ed25519PublicKey.isNotEmpty) {
      final deviceKeyHex = _hexEncode(device.ed25519PublicKey).toLowerCase();
      for (final peer in peers) {
        final peerKeyHex = peer.ed25519PublicKey?.toLowerCase();
        if (peerKeyHex != null && peerKeyHex == deviceKeyHex) {
          return _getPeerUrl(peer);
        }
      }
    }

    final deviceNameLower = device.name.toLowerCase();
    for (final peer in peers) {
      // Exact match on hostname attribute
      if (peer.deviceName != null &&
          peer.deviceName!.toLowerCase() == deviceNameLower) {
        return _getPeerUrl(peer);
      }
      // Exact match on mDNS service name (library name)
      if (peer.name.toLowerCase() == deviceNameLower) {
        return _getPeerUrl(peer);
      }
      // Partial: mDNS service name contains the device name
      if (peer.name.toLowerCase().contains(deviceNameLower) ||
          deviceNameLower.contains(peer.name.toLowerCase())) {
        return _getPeerUrl(peer);
      }
      // Partial: hostname contains the device name
      if (peer.deviceName != null &&
          (peer.deviceName!.toLowerCase().contains(deviceNameLower) ||
              deviceNameLower.contains(peer.deviceName!.toLowerCase()))) {
        return _getPeerUrl(peer);
      }
    }
    return null;
  }

  Future<void> _syncDevice(
    frb.FrbLinkedDevice device, {
    String direction = 'both',
  }) async {
    final syncProvider = context.read<DeviceSyncProvider>();
    // Always restart mDNS discovery before sync to get fresh peers
    await MdnsService.startDiscovery();
    await Future.delayed(const Duration(seconds: 3));
    final peerUrl = _findPeerUrl(device);
    debugPrint(
      'DevicePairing: sync device="${device.name}" peerUrl=$peerUrl direction=$direction '
      'peers=${MdnsService.peers.map((p) => '${p.name}(${p.deviceName})').toList()}',
    );
    await syncProvider.triggerSync(
      device.id,
      peerUrl: peerUrl,
      direction: direction,
    );
    if (!mounted) return;

    final result = syncProvider.lastResult;
    debugPrint(
      'DevicePairing: sync result sent=${result?.sentCount} received=${result?.receivedCount} pending=${result?.pendingReviewCount} error=${syncProvider.error}',
    );

    if (syncProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'pairing_error')}: ${syncProvider.error}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pendingReview = result?.pendingReviewCount ?? 0;

    // Build a clear, user-friendly message
    final String message;
    if (pendingReview > 0) {
      message = TranslationService.translate(
        context,
        'sync_done_with_pending',
      ).replaceFirst('%d', pendingReview.toString());
    } else {
      message = TranslationService.translate(context, 'sync_done');
    }

    // Capture navigator before showing snackbar (context may become invalid in snackbar action)
    final navigator = GoRouter.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: pendingReview > 0
            ? SnackBarAction(
                label: TranslationService.translate(
                  context,
                  'sync_pending_review_action',
                ),
                onPressed: () => navigator.go('/sync-review'),
              )
            : null,
      ),
    );

    // Refresh device list to update lastSynced timestamp
    _loadDevices();
  }

  void _showSyncMenu(frb.FrbLinkedDevice device, DeviceSyncProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _displayDeviceName(device),
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_rounded),
              title: Text(TranslationService.translate(context, 'sync_push')),
              onTap: () {
                Navigator.pop(sheetCtx);
                _syncDevice(device, direction: 'push');
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(TranslationService.translate(context, 'sync_pull')),
              onTap: () {
                Navigator.pop(sheetCtx);
                _syncDevice(device, direction: 'pull');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: Text(TranslationService.translate(context, 'sync_both')),
              onTap: () {
                Navigator.pop(sheetCtx);
                _syncDevice(device, direction: 'both');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded),
              title: Text(
                TranslationService.translate(context, 'sync_reset_all'),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _resetSync(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _resetSync(BuildContext ctx) async {
    final syncProvider = ctx.read<DeviceSyncProvider>();
    final count = await syncProvider.resetOperationLog();
    _backfillDone = false; // Allow backfill to run again
    if (mounted) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text('Reset $count operations')));
      _loadDevices();
    }
  }

  void _showPendingActions(
    BuildContext ctx,
    DeviceSyncProvider provider,
    int count,
  ) {
    showModalBottomSheet(
      context: ctx,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
              ),
              title: Text(
                TranslationService.translate(ctx, 'sync_review_approve_all'),
              ),
              subtitle: Text('$count operations'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final approved = await provider.approveAll();
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$approved operations approved')),
                  );
                  _loadDevices();
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_sweep_rounded,
                color: Colors.red,
              ),
              title: Text(TranslationService.translate(ctx, 'sync_reset_all')),
              subtitle: Text(
                TranslationService.translate(ctx, 'sync_reset_confirm'),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final deleted = await provider.resetOperationLog();
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$deleted operations deleted')),
                  );
                  _loadDevices();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeDevice(frb.FrbLinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'pairing_remove_confirm'),
        ),
        content: Text(_displayDeviceName(device)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              TranslationService.translate(context, 'delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await frb.deviceRemoveLinked(deviceId: device.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_remove_success'),
            ),
          ),
        );
        _loadDevices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'pairing_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMdnsToggle(ThemeData theme) {
    return Builder(
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        final isEnabled = themeProvider.networkDiscoveryEnabled;
        return Card(
          color: isEnabled
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wifi,
                      size: 20,
                      color: isEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                          context,
                          'settings_network_discovery',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: isEnabled,
                      onChanged: (value) async {
                        await themeProvider.setNetworkEnabled(value);
                        if (value && mounted) {
                          await Future.delayed(const Duration(seconds: 2));
                          if (mounted) _loadLocalPeers();
                        }
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    TranslationService.translate(context, 'pairing_mdns_hint'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _cancelPairing() {
    _countdownTimer?.cancel();
    _codeController.clear();
    _releaseWakelock();
    setState(() {
      _view = _PairingView.devices;
      _generatedCode = null;
      _pairingUrl = null;
      _scannedPeerUrl = null;
      _selectedPeer = null;
      _isGenerating = false;
      _isPairing = false;
    });
  }

  /// Keep the screen awake while a code is shown: on iOS, a screen lock
  /// suspends the embedded HTTP server and silently breaks pairing.
  void _enableWakelock() {
    WakelockPlus.enable().catchError((Object e) {
      debugPrint('DevicePairing: wakelock enable failed: $e');
    });
  }

  void _releaseWakelock() {
    WakelockPlus.disable().catchError((Object e) {
      debugPrint('DevicePairing: wakelock disable failed: $e');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String title;
    switch (_view) {
      case _PairingView.devices:
        title = TranslationService.translate(context, 'pairing_title');
      case _PairingView.showCode:
        title = TranslationService.translate(context, 'pairing_code_title');
      case _PairingView.enterCode:
        title = TranslationService.translate(context, 'pairing_enter_title');
    }

    return Scaffold(
      appBar: AppBar(
        leading: _view != _PairingView.devices
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: TranslationService.translate(
                  context,
                  'tooltip_cancel_pairing',
                ),
                onPressed: _cancelPairing,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: TranslationService.translate(context, 'back'),
                onPressed: () => context.go('/settings'),
              ),
        title: Semantics(header: true, child: Text(title)),
      ),
      body: AnimatedSwitcher(
        duration: AppDesign.standardDuration,
        child: _buildCurrentView(theme),
      ),
    );
  }

  Widget _buildCurrentView(ThemeData theme) {
    switch (_view) {
      case _PairingView.devices:
        return _buildDevicesView(theme);
      case _PairingView.showCode:
        return _buildShowCodeView(theme);
      case _PairingView.enterCode:
        return _buildEnterCodeView(theme);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Devices list view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDevicesView(ThemeData theme) {
    return Column(
      key: const ValueKey('devices'),
      children: [
        // Make the identity model explicit (ADR-039 Option B): paired devices
        // share their books but each keeps its own library identity.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Semantics(
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'pairing_identity_note',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoadingDevices
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) =>
                        _buildDeviceCard(_devices[index], theme),
                  ),
                ),
        ),
        // Action buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: TranslationService.translate(
                      context,
                      'tooltip_generate_pairing',
                    ),
                    child: FilledButton.icon(
                      onPressed: _generateCode,
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'pairing_generate_code',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesign.radiusMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: TranslationService.translate(
                      context,
                      'tooltip_enter_pairing',
                    ),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _loadLocalPeers();
                        setState(() => _view = _PairingView.enterCode);
                      },
                      icon: const Icon(Icons.keyboard),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'pairing_enter_code',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesign.radiusMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(context, 'pairing_empty_title'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              TranslationService.translate(context, 'pairing_empty_subtitle'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(frb.FrbLinkedDevice device, ThemeData theme) {
    final syncProvider = context.watch<DeviceSyncProvider>();
    final isSyncing = syncProvider.isSyncing;
    final pendingCount = syncProvider.pendingReviewCount;

    final lastSyncedLabel = _formatLastSynced(device.lastSynced);
    final pairedDate = _formatDate(device.createdAt ?? '');
    final pairedLabel = TranslationService.translate(
      context,
      'pairing_last_paired',
    ).replaceFirst('%s', pairedDate);

    return Semantics(
      button: true,
      label: '${_displayDeviceName(device)}, $lastSyncedLabel',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          onTap: isSyncing ? null : () => _showSyncMenu(device, syncProvider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading icon
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                  ),
                  child: isSyncing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.devices_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayDeviceName(device),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lastSyncedLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (pendingCount > 0) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _showPendingActions(
                            context,
                            syncProvider,
                            pendingCount,
                          ),
                          child: Text(
                            TranslationService.translate(
                              context,
                              'pairing_pending_review',
                            ).replaceFirst('%d', pendingCount.toString()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        pairedLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Trailing: just delete button (sync actions via card tap)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: TranslationService.translate(
                    context,
                    'tooltip_remove_device',
                  ),
                  onPressed: () => _removeDevice(device),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Show code view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShowCodeView(ThemeData theme) {
    if (_isGenerating) {
      return const Center(
        key: ValueKey('generating'),
        child: CircularProgressIndicator(),
      );
    }

    final code = _generatedCode ?? '';
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeStr =
        '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
    final progress = _remainingSeconds / 300.0;

    return SingleChildScrollView(
      key: const ValueKey('showCode'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Shield icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppDesign.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: AppDesign.glowShadow(theme.colorScheme.primary),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'pairing_code_instruction'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Code display - hero element
            _buildCodeSlots(code, theme),
            const SizedBox(height: 16),
            // Copy button
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.translate(context, 'copied'),
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text(TranslationService.translate(context, 'copy')),
            ),
            _buildPairingQr(theme),
            const SizedBox(height: 24),
            _buildMdnsToggle(theme),
            const SizedBox(height: 24),
            // Countdown
            SizedBox(
              width: 200,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        _remainingSeconds < 60
                            ? Colors.red
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.translate(
                      context,
                      'pairing_code_expires',
                    ).replaceFirst('%s', timeStr),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _remainingSeconds < 60
                          ? Colors.red
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            OutlinedButton(
              onPressed: _cancelPairing,
              child: Text(
                TranslationService.translate(context, 'pairing_cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeSlots(String code, ThemeData theme) {
    return Semantics(
      label:
          '${TranslationService.translate(context, 'pairing_code_title')}: ${code.split('').join(' ')}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(code.length, (i) {
            return Container(
              width: 48,
              height: 60,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 6,
                right: i == 2 ? 12 : 0, // visual gap after 3rd digit
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  code[i],
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// QR encoding `bibliogenius://pair?code&url` so the acceptor can scan it
  /// (auto-fills the code and a fresh target URL). Hidden if we have no LAN URL;
  /// the manual code path remains as fallback.
  Widget _buildPairingQr(ThemeData theme) {
    final code = _generatedCode;
    final url = _pairingUrl;
    if (code == null || url == null) return const SizedBox.shrink();
    final payload = Uri(
      scheme: 'bibliogenius',
      host: 'pair',
      queryParameters: {'code': code, 'url': url},
    ).toString();
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          TranslationService.translate(context, 'pairing_qr_caption'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          image: true,
          label: TranslationService.translate(context, 'pairing_qr_caption'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enter code view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEnterCodeView(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('enterCode'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Link icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppDesign.oceanGradient,
                shape: BoxShape.circle,
                boxShadow: AppDesign.glowShadow(const Color(0xFF0EA5E9)),
              ),
              child: const Icon(
                Icons.link_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(
                context,
                'pairing_enter_instruction',
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Fastest path: scan the QR shown on the other device. It carries
            // the code AND a fresh URL, so no manual entry or mDNS guesswork.
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _isPairing ? null : _scanPairingQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(
                  TranslationService.translate(context, 'pairing_scan_button'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildMdnsToggle(theme),
            const SizedBox(height: 16),
            // Peer selection
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_localPeers.isEmpty)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                            context,
                            'pairing_no_peers',
                          ),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: TranslationService.translate(
                          context,
                          'tooltip_scan_peers',
                        ),
                        onPressed: _loadLocalPeers,
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                      context,
                      'pairing_select_device',
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ..._localPeers.map(
                    (peer) => Card(
                      color: _selectedPeer == peer
                          ? theme.colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: Icon(
                          Icons.devices_rounded,
                          color: _selectedPeer == peer
                              ? theme.colorScheme.onPrimaryContainer
                              : null,
                        ),
                        title: Text(peer.name),
                        subtitle: Text(
                          peer.addresses.isNotEmpty
                              ? peer.addresses.first
                              : peer.host,
                        ),
                        trailing: _selectedPeer == peer
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () => setState(() {
                          _selectedPeer = peer;
                          _scannedPeerUrl = null;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            // Code input
            SizedBox(
              width: 280,
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 24,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _codeController.text.length == 6 &&
                        !_isPairing &&
                        (_selectedPeer != null || _scannedPeerUrl != null)
                    ? _acceptCode
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  ),
                ),
                child: _isPairing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        TranslationService.translate(
                          context,
                          'pairing_button_pair',
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancelPairing,
              child: Text(
                TranslationService.translate(context, 'pairing_cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Decode a hex string to bytes.
  static Uint8List _hexDecode(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Encode bytes to a lowercase hex string (to compare against the hex
  /// ed25519 key advertised over mDNS).
  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Display name for a linked device. Legacy records can be stored as
  /// "localhost" (iOS reports that as Platform.localHostname at pairing time);
  /// when the device is currently discoverable over mDNS, prefer its advertised
  /// library name, matched by stable ed25519 identity.
  String _displayDeviceName(frb.FrbLinkedDevice device) {
    final stored = device.name.trim();
    final looksBroken = stored.isEmpty || stored.toLowerCase() == 'localhost';
    if (!looksBroken) return stored;
    if (device.ed25519PublicKey.isNotEmpty) {
      final keyHex = _hexEncode(device.ed25519PublicKey).toLowerCase();
      for (final peer in MdnsService.peers) {
        if (peer.ed25519PublicKey?.toLowerCase() == keyHex &&
            peer.name.trim().isNotEmpty) {
          return peer.name.trim();
        }
      }
    }
    return stored;
  }

  /// A meaningful name to advertise to the paired device: the library name
  /// (what mDNS broadcasts and what the peer should display). Never
  /// Platform.localHostname, which iOS reports as "localhost".
  String _pairingDeviceName() {
    final libraryName = context.read<ThemeProvider>().libraryName.trim();
    if (libraryName.isNotEmpty) return libraryName;
    final host = Platform.localHostname;
    return (host.isEmpty || host == 'localhost') ? 'BiblioGenius' : host;
  }

  String _formatLastSynced(String? lastSynced) {
    if (lastSynced == null || lastSynced.isEmpty) {
      return TranslationService.translate(context, 'never_synced');
    }
    try {
      final dt = DateTime.parse(lastSynced);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) {
        return TranslationService.translate(context, 'synced_just_now');
      } else if (diff.inMinutes < 60) {
        return TranslationService.translate(
          context,
          'synced_minutes_ago',
        ).replaceFirst('%d', diff.inMinutes.toString());
      } else if (diff.inHours < 24) {
        return TranslationService.translate(
          context,
          'synced_hours_ago',
        ).replaceFirst('%d', diff.inHours.toString());
      } else {
        return TranslationService.translate(
          context,
          'synced_days_ago',
        ).replaceFirst('%d', diff.inDays.toString());
      }
    } catch (_) {
      return TranslationService.translate(context, 'never_synced');
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
