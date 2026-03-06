/// Native mDNS Service using Bonsoir
///
/// This service handles Bonjour/mDNS discovery on iOS, macOS, and other platforms
/// using native platform APIs for reliable local network discovery.
library;

import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Service type for BiblioGenius mDNS announcements
const String kServiceType = '_bibliogenius._tcp';

/// Discovered peer on the local network
class DiscoveredPeer {
  final String name;
  final String host;
  final int port;
  final List<String> addresses;
  final String? libraryId;
  final String? deviceName;
  /// Ed25519 public key (hex) from mDNS TXT record
  final String? ed25519PublicKey;
  /// X25519 public key (hex) from mDNS TXT record
  final String? x25519PublicKey;
  final DateTime discoveredAt;

  DiscoveredPeer({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
    this.libraryId,
    this.deviceName,
    this.ed25519PublicKey,
    this.x25519PublicKey,
    required this.discoveredAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'addresses': addresses,
    'library_id': libraryId,
    'device_name': deviceName,
    'ed25519_public_key': ed25519PublicKey,
    'x25519_public_key': x25519PublicKey,
    'discovered_at': discoveredAt.toIso8601String(),
  };
}

/// Native mDNS service for local network discovery
class MdnsService {
  /// Maximum number of discovered peers to keep in memory.
  /// Matches the Rust-side MAX_DISCOVERED_PEERS limit.
  static const int _maxPeers = 50;

  /// Peers not re-discovered within this duration are considered stale.
  static const Duration _staleTtl = Duration(seconds: 90);

  static BonsoirBroadcast? _broadcast;
  static BonsoirDiscovery? _discovery;
  static final Map<String, DiscoveredPeer> _peers = {};
  static StreamSubscription? _discoverySubscription;
  static bool _isRunning = false;
  static String? _ownServiceName;
  static String? _ownIp; // Our own IP for filtering

  /// Check if mDNS service is active
  static bool get isActive => _isRunning;

  /// Get discovered peers (excluding own service and stale entries).
  static List<DiscoveredPeer> get peers {
    _purgeStale();
    return _peers.values.toList();
  }

  /// Check if an IP address is a link-local address (169.254.x.x)
  /// These addresses are auto-assigned when DHCP fails and are not routable
  static bool _isLinkLocalAddress(String ip) {
    return ip.startsWith('169.254.');
  }

  /// Try to resolve a hostname via .local mDNS lookup
  /// Used as fallback when TXT record IP and service.host are unavailable
  static Future<String?> _resolveHostname(String hostname) async {
    try {
      // Ensure .local suffix for mDNS resolution
      final localName =
          hostname.endsWith('.local') ? hostname : '$hostname.local';
      final addresses = await InternetAddress.lookup(localName)
          .timeout(const Duration(seconds: 2));
      for (final addr in addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            !_isLinkLocalAddress(addr.address)) {
          debugPrint(
            '🔍 mDNS: Resolved $localName -> ${addr.address}',
          );
          return addr.address;
        }
      }
    } catch (e) {
      debugPrint('⚠️ mDNS: Failed to resolve hostname "$hostname" - $e');
    }
    return null;
  }

  /// Try to get a valid LAN IP from network interfaces.
  /// Returns the first non-link-local, non-loopback IPv4 address found.
  /// Public so it can be reused by other services (e.g., peer handshake, QR code).
  static Future<String?> getValidLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Priority 1: WiFi interfaces (en0, wlan0)
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.startsWith('en') || name.startsWith('wlan')) {
          for (final address in interface.addresses) {
            final ip = address.address;
            if (!address.isLoopback && !_isLinkLocalAddress(ip)) {
              debugPrint(
                '🔍 mDNS: Found WiFi IP $ip on ${interface.name} (Priority)',
              );
              return ip;
            }
          }
        }
      }

      // Priority 2: Other valid interfaces (fallback), excluding known cellular
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        // Skip cellular interfaces commonly found on mobile
        if (name.startsWith('pdp_ip') ||
            name.startsWith('rmnet') ||
            name.startsWith('ccmni')) {
          continue;
        }

        for (final address in interface.addresses) {
          final ip = address.address;
          if (!address.isLoopback && !_isLinkLocalAddress(ip)) {
            debugPrint('🔍 mDNS: Found fallback IP $ip on ${interface.name}');
            return ip;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ mDNS: Error listing network interfaces - $e');
    }
    return null;
  }

  /// Start announcing this library on the network
  static Future<bool> startAnnouncing(
    String libraryName,
    int port, {
    String? libraryId,
    String? ed25519PublicKey,
    String? x25519PublicKey,
  }) async {
    try {
      // Clean name for mDNS - keep Unicode letters, numbers, spaces, hyphens
      // Note: mDNS/Bonjour supports UTF-8 names, so we preserve accented chars
      final safeName = libraryName.replaceAll(
        RegExp(r'[^\p{L}\p{N}\s-]', unicode: true),
        '',
      );
      _ownServiceName = safeName;

      // Get local IP to include in attributes for reliable peer discovery
      // Filter out link-local addresses (169.254.x.x) as they're not routable
      String? localIp;
      try {
        final info = NetworkInfo();
        // Try WiFi IP first
        String? wifiIp = await info.getWifiIP();
        if (wifiIp != null && !_isLinkLocalAddress(wifiIp)) {
          localIp = wifiIp;
        }
        // If WiFi IP is link-local or null, try getting wired IP (on macOS/desktop)
        localIp ??= await getValidLanIp();
        if (localIp == null) {
          debugPrint(
            '⚠️ mDNS: No valid LAN IP found (only link-local available)',
          );
        }
      } catch (e) {
        debugPrint('⚠️ mDNS: Could not get local IP - $e');
      }

      final attributes = <String, String>{};
      if (libraryId != null) attributes['library_id'] = libraryId;
      if (localIp != null) {
        attributes['ip'] = localIp;
        _ownIp = localIp; // Store our IP for filtering
      }
      // Include device hostname for .local mDNS resolution fallback
      // (on macOS, ServiceResolvedEvent may not fire, so discovery
      // can resolve hostname.local via InternetAddress.lookup instead)
      // Note: iOS returns "localhost" which is useless for resolution.
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty && hostname != 'localhost') {
        attributes['hostname'] = hostname;
      }
      // E2EE public keys (64-char hex each, well within mDNS TXT limit)
      if (ed25519PublicKey != null) attributes['ed25519'] = ed25519PublicKey;
      if (x25519PublicKey != null) attributes['x25519'] = x25519PublicKey;

      final service = BonsoirService(
        name: safeName,
        type: kServiceType,
        port: port,
        attributes: attributes,
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
      _isRunning = true;

      debugPrint(
        '📡 mDNS: Broadcasting "$safeName" on port $port (IP: $localIp)',
      );
      return true;
    } catch (e) {
      debugPrint('❌ mDNS: Failed to start broadcasting - $e');
      return false;
    }
  }

  /// Start discovering other libraries on the network
  static Future<bool> startDiscovery() async {
    try {
      // Stop any existing discovery first to avoid duplicates
      await stopDiscovery();

      // Clear cached peers to start fresh
      _peers.clear();
      debugPrint('🧹 mDNS: Cleared peer cache before discovery');

      _discovery = BonsoirDiscovery(type: kServiceType);
      await _discovery!.initialize();
      debugPrint('🔍 mDNS: Discovery initialized for type: $kServiceType');
      debugPrint('🔍 mDNS: Own service name to filter: $_ownServiceName');

      _discoverySubscription = _discovery!.eventStream?.listen(
        (event) {
          debugPrint('📡 mDNS: Received event: ${event.runtimeType}');
          // Handle service found - add immediately as workaround for macOS sandbox
          // (ServiceResolvedEvent doesn't fire reliably in Flutter sandbox)
          if (event is BonsoirDiscoveryServiceFoundEvent) {
            _handleServiceFound(event.service);
          }
          // Handle service resolved (preferred if it fires)
          else if (event is BonsoirDiscoveryServiceResolvedEvent) {
            _handleServiceResolved(event.service);
          }
          // Handle service lost
          else if (event is BonsoirDiscoveryServiceLostEvent) {
            final service = event.service;
            // Try to find and remove by matching name (since we don't have the key)
            final keysToRemove = _peers.entries
                .where(
                  (e) =>
                      e.value.name ==
                      service.name.replaceAll(RegExp(r'\s*\(\d+\)$'), ''),
                )
                .map((e) => e.key)
                .toList();
            for (final key in keysToRemove) {
              _peers.remove(key);
              debugPrint('👋 mDNS: Lost "${service.name}" (key: $key)');
            }
          }
        },
        onError: (error) {
          debugPrint('❌ mDNS: Error in discovery stream - $error');
          // Handle stream errors (like defunct connection) gracefully
          // We don't want to crash the app, just log and maybe cleanup
          // If needed, we could implement a retry mechanism here
          stopDiscovery();
        },
      );

      await _discovery!.start();
      debugPrint('🔍 mDNS: Discovery started');
      return true;
    } catch (e) {
      debugPrint('❌ mDNS: Failed to start discovery - $e');
      return false;
    }
  }

  /// Remove peers that haven't been re-discovered within the TTL window.
  static void _purgeStale() {
    final cutoff = DateTime.now().subtract(_staleTtl);
    final staleKeys = _peers.entries
        .where((e) => e.value.discoveredAt.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    for (final key in staleKeys) {
      debugPrint('🕐 mDNS: Purging stale peer "${_peers[key]?.name}" ($key)');
      _peers.remove(key);
    }
  }

  /// Helper to register a peer once we have a valid host
  static void _addPeer(BonsoirService service, String host) {
    final actualPort = service.port > 0 ? service.port : 8000;
    final cleanName = service.name.replaceAll(
      RegExp(r'\s*\(\d+\)$'),
      '',
    );
    final peerKey = '$host:$actualPort';

    final peer = DiscoveredPeer(
      name: cleanName,
      host: host,
      port: actualPort,
      addresses: [host],
      libraryId: service.attributes['library_id'],
      deviceName: service.attributes['hostname'],
      ed25519PublicKey: service.attributes['ed25519'],
      x25519PublicKey: service.attributes['x25519'],
      discoveredAt: DateTime.now(),
    );

    // Evict oldest peer if at capacity (before inserting, unless key already exists)
    if (_peers.length >= _maxPeers && !_peers.containsKey(peerKey)) {
      final oldestKey = _peers.entries
          .reduce((a, b) =>
              a.value.discoveredAt.isBefore(b.value.discoveredAt) ? a : b)
          .key;
      _peers.remove(oldestKey);
      debugPrint(
        '⚠️ mDNS: Peer limit ($_maxPeers) reached, evicted oldest entry',
      );
    }

    _peers[peerKey] = peer;
    debugPrint('📚 mDNS: Discovered "$cleanName" at $peerKey');
  }

  /// Check if a service is our own (should be filtered out)
  static bool _isOwnService(BonsoirService service) {
    final peerIp = service.attributes['ip'];

    // Skip by IP (most reliable)
    if (_ownIp != null && peerIp == _ownIp) {
      debugPrint(
        '🔇 mDNS: Skipping own service by IP: ${service.name} ($peerIp)',
      );
      return true;
    }

    // Skip by name as fallback (handle Bonjour auto-suffix like "(2)")
    final cleanName = service.name.replaceAll(
      RegExp(r'\s*\(\d+\)$'),
      '',
    );
    if (_ownServiceName != null && cleanName == _ownServiceName && peerIp == null) {
      debugPrint(
        '🔇 mDNS: Skipping own service by name (no IP): ${service.name}',
      );
      return true;
    }

    return false;
  }

  /// Resolve host IP from a service, trying multiple strategies:
  /// 1. IP from TXT record attributes (most reliable)
  /// 2. Resolved host from Bonsoir
  /// 3. Hostname.local mDNS lookup (fallback for macOS where resolve events
  ///    don't fire reliably)
  static Future<String?> _resolveServiceHost(BonsoirService service) async {
    // Strategy 1: IP from TXT attributes
    final ipFromAttrs = service.attributes['ip'];
    if (ipFromAttrs != null &&
        ipFromAttrs.isNotEmpty &&
        !_isLinkLocalAddress(ipFromAttrs)) {
      debugPrint('📚 mDNS: Using IP from attributes: $ipFromAttrs');
      return ipFromAttrs;
    }

    // Strategy 2: Bonsoir resolved host
    if (service.host != null &&
        service.host!.isNotEmpty &&
        !_isLinkLocalAddress(service.host!)) {
      debugPrint(
        '📚 mDNS: Using resolved host for "${service.name}": ${service.host}',
      );
      return service.host;
    }

    // Strategy 3: Resolve hostname.local via DNS
    // This is critical on macOS where ServiceResolvedEvent often doesn't fire
    final hostname = service.attributes['hostname'];
    if (hostname != null && hostname.isNotEmpty) {
      debugPrint(
        '📚 mDNS: Attempting hostname.local resolution for "${service.name}" ($hostname)',
      );
      final resolved = await _resolveHostname(hostname);
      if (resolved != null) return resolved;
    }

    // All strategies exhausted
    if (ipFromAttrs != null && _isLinkLocalAddress(ipFromAttrs)) {
      debugPrint(
        '⚠️ mDNS: Peer advertised link-local IP ($ipFromAttrs), skipping',
      );
    } else {
      debugPrint(
        '⚠️ mDNS: No valid IP for "${service.name}" after all resolution strategies',
      );
    }
    return null;
  }

  /// Handle ServiceFoundEvent - async to allow hostname.local resolution
  static Future<void> _handleServiceFound(BonsoirService service) async {
    if (_isOwnService(service)) return;

    final host = await _resolveServiceHost(service);
    if (host == null) return;

    _addPeer(service, host);
  }

  /// Handle ServiceResolvedEvent - async to allow hostname.local fallback
  static Future<void> _handleServiceResolved(BonsoirService service) async {
    if (_isOwnService(service)) return;

    final host = await _resolveServiceHost(service);
    if (host == null) return;

    _addPeer(service, host);
  }

  /// Get peers as JSON-compatible maps (for API compatibility)
  static List<Map<String, dynamic>> getPeersJson() {
    return _peers.values.map((p) => p.toJson()).toList();
  }

  /// Stop discovery only (keep broadcast running)
  static Future<void> stopDiscovery() async {
    try {
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      await _discovery?.stop();
      _discovery = null;
      debugPrint('🔍 mDNS: Discovery stopped');
    } catch (e) {
      debugPrint('⚠️ mDNS: Error stopping discovery - $e');
    }
  }

  /// Stop mDNS service completely
  static Future<void> stop() async {
    try {
      await stopDiscovery();
      await _broadcast?.stop();
      _broadcast = null;
      _peers.clear();
      _isRunning = false;
      _ownServiceName = null;
      _ownIp = null;
      debugPrint('📡 mDNS: Service stopped');
    } catch (e) {
      debugPrint('⚠️ mDNS: Error stopping - $e');
    }
  }

  /// Restart mDNS service (useful after hot reload or network changes)
  /// Requires the same parameters as startAnnouncing
  static Future<bool> restart(
    String libraryName,
    int port, {
    String? libraryId,
    String? ed25519PublicKey,
    String? x25519PublicKey,
  }) async {
    debugPrint('🔄 mDNS: Restarting service...');
    await stop();
    // Small delay to ensure cleanup is complete
    await Future.delayed(const Duration(milliseconds: 500));
    final announceResult = await startAnnouncing(
      libraryName,
      port,
      libraryId: libraryId,
      ed25519PublicKey: ed25519PublicKey,
      x25519PublicKey: x25519PublicKey,
    );
    if (announceResult) {
      await startDiscovery();
      debugPrint('✅ mDNS: Service restarted successfully');
      return true;
    }
    debugPrint('❌ mDNS: Failed to restart service');
    return false;
  }
}
