import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../src/rust/api/frb.dart' show FrbNudgeEvent, subscribeRelayNudges;

/// Tracks the count of pending peer connection requests
/// and detects newly connected peers for flash notifications.
class PendingPeersProvider extends ChangeNotifier {
  final ApiService _apiService;
  int _pendingCount = 0;
  Timer? _refreshTimer;
  StreamSubscription<FrbNudgeEvent>? _nudgeSub;

  // Tracks known peer IDs to detect new connections
  Set<int> _knownPeerIds = {};
  bool _knownPeersSeeded = false;

  /// Called when a new peer is detected (accepted or pending).
  /// Map keys: id, name, url, library_uuid, connection_status,
  /// relay_url, mailbox_id, relay_write_token.
  void Function(Map<String, dynamic> peer)? onNewPeerDetected;

  PendingPeersProvider(this._apiService) {
    refresh();
    // Auto-refresh every 30 seconds (fallback safety net)
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refresh(),
    );
    // Instant refresh on relay nudge (ADR-017)
    _subscribeNudgeStream();
  }

  /// Subscribe to the FFI relay nudge stream for instant refresh.
  void _subscribeNudgeStream() {
    _nudgeSub?.cancel();
    try {
      _nudgeSub = subscribeRelayNudges().listen(
        (_) => refresh(),
        onError: (Object e) {
          debugPrint('PendingPeersProvider: nudge stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint(
        'PendingPeersProvider: failed to subscribe to nudge stream: $e',
      );
    }
  }

  int get pendingCount => _pendingCount;

  Future<void> refresh() async {
    try {
      final response = await _apiService.getPendingPeers();
      final requests = response.data['requests'] as List? ?? [];
      final newCount = requests.length;
      if (newCount != _pendingCount) {
        _pendingCount = newCount;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PendingPeersProvider: Error fetching pending peers: $e');
    }

    // Detect newly connected/pending peers
    await _detectNewPeers();
  }

  Future<void> _detectNewPeers() async {
    if (onNewPeerDetected == null) return;
    try {
      final res = await _apiService.getPeers();
      final data = res.data;
      List allPeers = [];
      if (data is Map && data['data'] != null) {
        allPeers = data['data'] as List;
      } else if (data is List) {
        allPeers = data;
      }

      final currentIds = <int>{};
      for (final p in allPeers) {
        final id = p['id'] as int?;
        if (id != null) currentIds.add(id);
      }

      if (!_knownPeersSeeded) {
        // First poll: seed without triggering notifications
        _knownPeerIds = currentIds;
        _knownPeersSeeded = true;
        return;
      }

      final newIds = currentIds.difference(_knownPeerIds);
      _knownPeerIds = currentIds;

      for (final newId in newIds) {
        final peer = allPeers.firstWhere(
          (p) => p['id'] == newId,
          orElse: () => null,
        );
        if (peer != null) {
          onNewPeerDetected!(Map<String, dynamic>.from(peer as Map));
        }
      }
    } catch (e) {
      debugPrint('PendingPeersProvider: Error detecting new peers: $e');
    }
  }

  void decrement() {
    if (_pendingCount > 0) {
      _pendingCount--;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _nudgeSub?.cancel();
    super.dispose();
  }
}
