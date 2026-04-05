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
  final Map<String, _PeerBackoff> _backoff = {};

  SyncService(this._apiService, {required bool Function() isLanEnabled})
      : _isLanEnabled = isLanEnabled;

  /// Reset backoff for a specific peer (e.g. on manual refresh).
  void resetBackoff(String url) {
    _backoff.remove(url);
  }

  Future<void> syncAllPeers() async {
    try {
      final response = await _apiService.getPeers();
      if (response.statusCode == 200) {
        final List peers = response.data['data'] ?? [];
        final now = DateTime.now();
        // Sync all peers in parallel to avoid one offline peer blocking the rest
        await Future.wait(
          peers.map((peer) async {
            final url = peer['url'] as String;
            final name = peer['name'] ?? url;

            // Skip peers still in backoff
            final bo = _backoff[url];
            if (bo != null && now.isBefore(bo.nextRetry)) {
              debugPrint("Skipping peer $name (backoff until ${bo.nextRetry})");
              return;
            }

            try {
              await _apiService.syncPeer(url, skipLan: !_isLanEnabled());
              _backoff.remove(url);
              debugPrint("Synced peer $name");
            } catch (e) {
              final failures = (bo?.failures ?? 0) + 1;
              _backoff[url] = _PeerBackoff(
                failures: failures,
                nextRetry: now.add(_PeerBackoff.backoffDuration(failures)),
              );
              debugPrint("Failed to sync peer $name (attempt $failures, next retry in ${_PeerBackoff.backoffDuration(failures).inSeconds}s): $e");
            }
          }),
        );
      }
    } catch (e) {
      debugPrint("Failed to fetch peers for sync: $e");
    }
  }
}
