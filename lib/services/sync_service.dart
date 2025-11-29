import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SyncService {
  final ApiService _apiService;

  SyncService(this._apiService);

  Future<void> syncAllPeers() async {
    try {
      final response = await _apiService.getPeers();
      if (response.statusCode == 200) {
        final List peers = response.data;
        for (var peer in peers) {
          try {
            await _apiService.syncPeer(peer['id']);
            debugPrint("Synced peer ${peer['id']}");
          } catch (e) {
            debugPrint("Failed to sync peer ${peer['id']}: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch peers for sync: $e");
    }
  }
}
