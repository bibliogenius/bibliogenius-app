import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/sync_service.dart';

// A relay sync fails only after the backend gave up waiting (about 110 s).
// The backoff must start when the failure is known, not when the sync began,
// otherwise a 30 s penalty has already expired by the time it is recorded.

const _peerUrl = 'http://192.168.1.10:8080';

class _MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake';
}

class _FakeClock {
  DateTime current = DateTime(2026, 11, 10, 12);
  DateTime now() => current;
  void advance(Duration d) => current = current.add(d);
}

class _SlowApi extends ApiService {
  _SlowApi(this.clock) : super(_MockAuthService(), baseUrl: 'http://mock');

  final _FakeClock clock;
  int calls = 0;
  bool shouldThrow = true;
  Duration duration = const Duration(seconds: 100);
  Completer<void>? gate;

  @override
  Future<Response> getPeers() async => Response(
    requestOptions: RequestOptions(path: '/api/peers'),
    statusCode: 200,
    data: {
      'data': [
        {'url': _peerUrl, 'name': 'MacBook'},
      ],
    },
  );

  @override
  Future<Response> syncPeer(String peerUrl, {bool skipLan = false}) async {
    calls++;
    if (gate != null) await gate!.future;
    clock.advance(duration);
    if (shouldThrow) throw Exception('relay: no answer');
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
      statusCode: 200,
      data: {'message': 'ok'},
    );
  }
}

void main() {
  late _FakeClock clock;
  late _SlowApi api;
  late SyncService svc;

  setUp(() {
    clock = _FakeClock();
    api = _SlowApi(clock);
    svc = SyncService(
      api,
      isLanEnabled: () => true,
      checkConnectivity: () async => [ConnectivityResult.mobile],
      now: clock.now,
    );
  });

  group('SyncService backoff after a slow failure', () {
    test('the first penalty runs from the end of the failed sync', () async {
      await svc.syncAllPeers(); // fails at t+100 s
      expect(api.calls, 1);

      clock.advance(const Duration(seconds: 10)); // t+110 s
      await svc.syncAllPeers();
      expect(api.calls, 1, reason: 'still inside the 30 s penalty');

      clock.advance(const Duration(seconds: 21)); // t+131 s
      await svc.syncAllPeers();
      expect(api.calls, 2, reason: 'penalty over');
    });

    test('the second penalty also runs from the end of the sync', () async {
      await svc.syncAllPeers(); // fails at t+100 s
      clock.advance(const Duration(seconds: 31));
      await svc.syncAllPeers(); // fails at t+231 s, penalty 2 min
      expect(api.calls, 2);

      clock.advance(const Duration(seconds: 100)); // t+331 s
      await svc.syncAllPeers();
      expect(api.calls, 2, reason: 'still inside the 2 min penalty');
    });
  });

  group('SyncService with a sync still running for a peer', () {
    // The periodic round fires every 30 s while a relay sync can take far
    // longer. A second request for the same peer only fills its mailbox.
    test('a new round does not sync that peer a second time', () async {
      api.gate = Completer<void>();
      final first = svc.syncAllPeers();
      await pumpEventQueue();
      expect(api.calls, 1);

      await svc.syncAllPeers();
      expect(api.calls, 1, reason: 'the first sync has not returned yet');

      api.gate!.complete();
      await first;
    });

    test('the peer is synced again once the running sync returned', () async {
      api.shouldThrow = false;
      api.gate = Completer<void>();
      final first = svc.syncAllPeers();
      await pumpEventQueue();
      api.gate!.complete();
      await first;

      api.gate = null;
      await svc.syncAllPeers();
      expect(api.calls, 2);
    });

    test('a failed sync releases the peer for a later round', () async {
      await svc.syncAllPeers(); // fails, 30 s penalty
      clock.advance(const Duration(seconds: 31));

      await svc.syncAllPeers();
      expect(api.calls, 2);
    });
  });
}
