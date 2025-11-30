import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SyncService {
  final ApiService _apiService;

  SyncService(this._apiService);

  Future<void> syncAllPeers() async {
    try {
      final response = await _apiService.getPeers();
      if (response.statusCode == 200) {
        final List peers = response.data['data'] ?? [];
        for (var peer in peers) {
          try {
            await _apiService.syncPeer(peer['url']);
            debugPrint("Synced peer ${peer['name']}");
          } catch (e) {
            debugPrint("Failed to sync peer ${peer['name']}: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch peers for sync: $e");
    }
  }
}
