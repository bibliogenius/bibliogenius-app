import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class _PeerBackoff {
  int failures;
  DateTime nextRetry;

  _PeerBackoff({required this.failures, required this.nextRetry});

  static Duration backoffDuration(int failures) {
    return switch (failures) {
      1 => const Duration(seconds: 30),
      2 => const Duration(minutes: 2),
      3 => const Duration(minutes: 10),
      _ => const Duration(minutes: 30),
    };
  }
}

class SyncService {
  final ApiService _apiService;
  final bool Function() _isLanEnabled;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final bool Function(String url) _isPeerDiscovered;
  final Map<String, _PeerBackoff> _backoff = {};

  SyncService(
    this._apiService, {
    required bool Function() isLanEnabled,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    bool Function(String url)? isPeerDiscovered,
  }) : _isLanEnabled = isLanEnabled,
       _checkConnectivity =
           checkConnectivity ?? (() => Connectivity().checkConnectivity()),
       _isPeerDiscovered = isPeerDiscovered ?? ((_) => false);

  /// Reset backoff for a specific peer (e.g. on manual refresh).
  void resetBackoff(String url) {
    _backoff.remove(url);
  }

  /// Forget every peer's backoff penalty. Called on an explicit manual
  /// pull-to-refresh so the user's "retry now" gesture is honored even for
  /// peers still inside their backoff window.
  void resetAllBackoff() {
    _backoff.clear();
  }

  Future<void> syncAllPeers() async {
    try {
      final response = await _apiService.getPeers();
      if (response.statusCode == 200) {
        final List peers = response.data['data'] ?? [];
        final now = DateTime.now();

        // Check actual network type: skip direct LAN when not on WiFi/ethernet
        // (avoids 15s timeouts per peer on mobile data).
        // On error, default to allowing LAN (previous behavior).
        bool hasLan = true;
        try {
          final connectivity = await _checkConnectivity();
          hasLan =
              connectivity.contains(ConnectivityResult.wifi) ||
              connectivity.contains(ConnectivityResult.ethernet);
        } catch (e) {
          debugPrint(
            'SyncService: connectivity check failed ($e), assuming LAN available',
          );
        }
        final skipLan = !hasLan || !_isLanEnabled();
        if (!hasLan) {
          debugPrint(
            'SyncService: not on WiFi/ethernet, skipping direct LAN sync',
          );
        }

        // Sync all peers in parallel to avoid one offline peer blocking the rest
        await Future.wait(
          peers.map((peer) async {
            final url = peer['url'] as String;
            final name = peer['name'] ?? url;

            // Skip peers still in backoff, unless mDNS currently sees the peer
            // on the LAN: a live announcement proves it is reachable now (e.g.
            // an iOS peer whose embedded server was suspended in the background
            // is back to the foreground), so a fresh discovery overrides the
            // backoff penalty and lets us retry immediately.
            final bo = _backoff[url];
            if (bo != null && now.isBefore(bo.nextRetry)) {
              if (_isPeerDiscovered(url)) {
                _backoff.remove(url);
              } else {
                debugPrint(
                  "Skipping peer $name (backoff until ${bo.nextRetry})",
                );
                return;
              }
            }

            try {
              await _apiService.syncPeer(url, skipLan: skipLan);
              _backoff.remove(url);
              debugPrint("Synced peer $name");
            } catch (e) {
              final failures = (bo?.failures ?? 0) + 1;
              _backoff[url] = _PeerBackoff(
                failures: failures,
                nextRetry: now.add(_PeerBackoff.backoffDuration(failures)),
              );
              debugPrint(
                "Failed to sync peer $name (attempt $failures, next retry in ${_PeerBackoff.backoffDuration(failures).inSeconds}s): $e",
              );
            }
          }),
        );
      }
    } catch (e) {
      debugPrint("Failed to fetch peers for sync: $e");
    }
  }
}
