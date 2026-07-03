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

  group('SyncService mDNS-aware backoff', () {
    // A peer that iOS suspends in the background legitimately fails the LAN
    // connectivity check and enters backoff (up to 30 min). When the peer
    // comes back to the foreground it re-announces over mDNS, which is proof
    // it is reachable *now*. A fresh mDNS discovery must therefore clear the
    // peer's backoff so the very next sync retries it instead of waiting out
    // the penalty. Regression guard for the "stuck on Internet/hub for 30 min
    // even though the peer is live on the LAN" bug.
    test(
      'fresh mDNS discovery clears backoff so a returned peer is retried',
      () async {
        mockApi.shouldThrow = true;
        // Only the iPhone will be re-discovered on the LAN; the MacBook stays
        // absent and must remain in backoff.
        var iphoneOnLan = false;
        final svc = SyncService(
          mockApi,
          isLanEnabled: () => true,
          checkConnectivity: () async => [ConnectivityResult.wifi],
          isPeerDiscovered: (url) =>
              iphoneOnLan && url == 'http://192.168.1.20:8080',
        );

        // Round 1: both peers unreachable -> both enter backoff.
        await svc.syncAllPeers();
        expect(mockApi.syncedUrls, isEmpty);

        // The iPhone re-announces over mDNS (app back to foreground) and is up.
        iphoneOnLan = true;
        mockApi.shouldThrow = false;

        // Round 2: the freshly discovered peer bypasses its backoff and is
        // retried; the still-absent MacBook remains skipped.
        await svc.syncAllPeers();
        expect(mockApi.syncedUrls, ['http://192.168.1.20:8080']);
      },
    );

    test(
      'without mDNS discovery the backoff is still honored (no regression)',
      () async {
        mockApi.shouldThrow = true;
        final svc = SyncService(
          mockApi,
          isLanEnabled: () => true,
          checkConnectivity: () async => [ConnectivityResult.wifi],
          isPeerDiscovered: (_) => false,
        );

        await svc.syncAllPeers();
        expect(mockApi.syncedUrls, isEmpty);

        // Peer is NOT discovered on the LAN -> backoff must keep skipping it.
        mockApi.shouldThrow = false;
        await svc.syncAllPeers();
        expect(mockApi.syncedUrls, isEmpty);
      },
    );
  });

  group('SyncService manual refresh', () {
    // A manual pull-to-refresh is an explicit user request to retry now, so it
    // must forget every peer's backoff penalty instead of silently skipping
    // peers that are still in their backoff window.
    test('resetAllBackoff clears penalties so peers are retried', () async {
      mockApi.shouldThrow = true;
      final svc = SyncService(
        mockApi,
        isLanEnabled: () => true,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );

      // Both peers fail -> both enter backoff.
      await svc.syncAllPeers();
      expect(mockApi.syncedUrls, isEmpty);

      // Manual pull-to-refresh forgets the penalties.
      svc.resetAllBackoff();
      mockApi.shouldThrow = false;

      await svc.syncAllPeers();
      expect(mockApi.syncedUrls.length, 2);
    });
  });
}
