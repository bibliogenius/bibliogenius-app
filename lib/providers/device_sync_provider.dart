import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../src/rust/api/frb.dart' as frb;

class DeviceSyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  String? _error;
  frb.FrbSyncResult? _lastResult;
  List<frb.FrbPendingReviewOp> _pendingReview = [];
  bool _isLoadingReview = false;

  // Getters
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  frb.FrbSyncResult? get lastResult => _lastResult;
  List<frb.FrbPendingReviewOp> get pendingReview => _pendingReview;
  bool get isLoadingReview => _isLoadingReview;
  int get pendingReviewCount => _pendingReview.length;

  /// Trigger sync with a linked device via the local HTTP endpoint
  /// which handles the actual E2EE transport.
  /// [peerUrl] is the LAN URL of the peer (from mDNS discovery).
  /// [direction] is "push" (master→slave), "pull" (slave←master), or "both" (default).
  Future<void> triggerSync(int deviceId, {String? peerUrl, String direction = 'both'}) async {
    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      // Call the real HTTP endpoint that handles E2EE transport
      final dio = Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:${ApiService.httpPort}',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final response = await dio.post(
        '/api/devices/sync/$deviceId',
        data: {
          if (peerUrl != null) 'peer_url': peerUrl,
          'direction': direction,
        },
      );
      final data = response.data as Map<String, dynamic>;

      _lastResult = frb.FrbSyncResult(
        sentCount: (data['sent_count'] as num?)?.toInt() ?? 0,
        receivedCount: (data['received_count'] as num?)?.toInt() ?? 0,
        pendingReviewCount: (data['pending_review_count'] as num?)?.toInt() ?? 0,
      );
      // Refresh pending review list after sync
      await _loadPendingReviewSilent();
    } on DioException catch (e) {
      final responseData = e.response?.data;
      _error = responseData is Map ? responseData['error']?.toString() ?? e.message : e.message;
      debugPrint('DeviceSyncProvider.triggerSync error: status=${e.response?.statusCode} body=$responseData');
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.triggerSync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Load pending review operations
  Future<void> loadPendingReview() async {
    _isLoadingReview = true;
    _error = null;
    notifyListeners();

    try {
      _pendingReview = await frb.deviceSyncPendingReview();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.loadPendingReview error: $e');
    } finally {
      _isLoadingReview = false;
      notifyListeners();
    }
  }

  /// Internal reload without loading indicator
  Future<void> _loadPendingReviewSilent() async {
    try {
      _pendingReview = await frb.deviceSyncPendingReview();
    } catch (e) {
      debugPrint('DeviceSyncProvider._loadPendingReviewSilent error: $e');
    }
  }

  /// Approve specific operations by IDs
  Future<int> approveOps(List<int> ids) async {
    try {
      final count = await frb.deviceSyncApprove(ids: ids);
      _pendingReview.removeWhere((op) => ids.contains(op.id));
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.approveOps error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Reject specific operations by IDs
  Future<int> rejectOps(List<int> ids) async {
    try {
      final count = await frb.deviceSyncReject(ids: ids);
      _pendingReview.removeWhere((op) => ids.contains(op.id));
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.rejectOps error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Approve all pending review operations
  Future<int> approveAll() async {
    try {
      final count = await frb.deviceSyncApproveAll();
      _pendingReview.clear();
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.approveAll error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Reset: purge the entire operation log
  Future<int> resetOperationLog() async {
    try {
      final count = await frb.deviceSyncReset();
      _pendingReview.clear();
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.resetOperationLog error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Reject all pending review operations
  Future<int> rejectAll() async {
    try {
      final count = await frb.deviceSyncRejectAll();
      _pendingReview.clear();
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.rejectAll error: $e');
      notifyListeners();
      return 0;
    }
  }
}
