import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/sync_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake';
}

class _MockApiService extends ApiService {
  _MockApiService() : super(_MockAuthService(), baseUrl: 'http://mock');

  List<String> syncedUrls = [];
  Map<String, bool> syncSkipLan = {};
  bool shouldThrow = false;

  @override
  Future<Response> getPeers() async {
    return Response(
      requestOptions: RequestOptions(path: '/api/peers'),
      statusCode: 200,
      data: {
        'data': [
          {'url': 'http://192.168.1.10:8080', 'name': 'MacBook'},
          {'url': 'http://192.168.1.20:8080', 'name': 'iPhone'},
        ],
      },
    );
  }

  @override
  Future<Response> syncPeer(String peerUrl, {bool skipLan = false}) async {
    if (shouldThrow) throw Exception('sync failed');
    syncedUrls.add(peerUrl);
    syncSkipLan[peerUrl] = skipLan;
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
      statusCode: 200,
      data: {'message': 'ok'},
    );
  }
}

void main() {
  late _MockApiService mockApi;

  setUp(() {
    mockApi = _MockApiService();
  });

  group('SyncService connectivity check', () {
    test(
      'on WiFi: syncPeer called with skipLan=false when LAN enabled',
      () async {
        final svc = SyncService(
          mockApi,
          isLanEnabled: () => true,
          checkConnectivity: () async => [ConnectivityResult.wifi],
        );

        await svc.syncAllPeers();

        expect(mockApi.syncedUrls.length, 2);
        expect(mockApi.syncSkipLan['http://192.168.1.10:8080'], false);
        expect(mockApi.syncSkipLan['http://192.168.1.20:8080'], false);
      },
    );

    test('on mobile: syncPeer called with skipLan=true', () async {
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => [ConnectivityResult.mobile],
      );

      await svc.syncAllPeers();

      expect(mockApi.syncedUrls.length, 2);
      expect(mockApi.syncSkipLan['http://192.168.1.10:8080'], true);
      expect(mockApi.syncSkipLan['http://192.168.1.20:8080'], true);
    });

    test('on WiFi but LAN disabled by user: skipLan=true', () async {
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => false,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );

      await svc.syncAllPeers();

      expect(mockApi.syncSkipLan.values.every((v) => v == true), true);
    });

    test('on ethernet: skipLan=false when LAN enabled', () async {
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => [ConnectivityResult.ethernet],
      );

      await svc.syncAllPeers();

      expect(mockApi.syncSkipLan.values.every((v) => v == false), true);
    });

    test('connectivity check throws: defaults to LAN available', () async {
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => throw Exception('platform error'),
      );

      await svc.syncAllPeers();

      // Should still sync (fallback hasLan=true)
      expect(mockApi.syncedUrls.length, 2);
      expect(mockApi.syncSkipLan.values.every((v) => v == false), true);
    });

    test('no connectivity: skipLan=true', () async {
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => [ConnectivityResult.none],
      );

      await svc.syncAllPeers();

      expect(mockApi.syncSkipLan.values.every((v) => v == true), true);
    });

    test('backoff after failure is preserved across sync rounds', () async {
      mockApi.shouldThrow = true;
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );

      // First round: both peers fail -> enter backoff
      await svc.syncAllPeers();
      expect(mockApi.syncedUrls, isEmpty); // throws before adding to list

      // Second round immediately: peers should be skipped (backoff)
      mockApi.shouldThrow = false;
      await svc.syncAllPeers();
      expect(mockApi.syncedUrls, isEmpty); // still in backoff
    });
  });
}
