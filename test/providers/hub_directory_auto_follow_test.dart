import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const _selfNode = 'self-node-uuid';
const _pairedNode = 'paired-peer-uuid';
const _strangerNode = 'stranger-node-uuid';

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.0.0';
}

/// FFI mock recording follow / resolve calls (ADR-053 reconciliation).
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  final List<String> followedNodes = [];
  final List<(int, String)> resolvedFollows = [];

  /// Active follows the local library already holds.
  List<frb.FrbHubFollow> following = [];

  /// Pending incoming follow requests.
  List<frb.FrbHubFollow> pending = [];

  int listFollowingCalls = 0;
  int pendingRequestsCalls = 0;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      const frb.FrbDirectoryConfig(
        nodeId: _selfNode,
        isListed: true,
        requiresApproval: true,
        acceptFrom: 'everyone',
        allowBorrowing: false,
      );

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async {
    listFollowingCalls++;
    return following;
  }

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => [];

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async {
    pendingRequestsCalls++;
    return pending;
  }

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async {
    followedNodes.add(nodeId);
    return frb.FrbHubFollow(
      id: 99,
      followerNodeId: _selfNode,
      followedNodeId: nodeId,
      status: 'pending',
      createdAt: '2026-07-16T00:00:00Z',
    );
  }

  @override
  Future<frb.FrbHubFollow?> hubDirectoryResolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
  }) async {
    resolvedFollows.add((followId, resolution));
    pending = pending.where((f) => f.id != followId).toList();
    return frb.FrbHubFollow(
      id: followId,
      followerNodeId: _pairedNode,
      followedNodeId: _selfNode,
      status: resolution == 'approve' ? 'active' : resolution,
      createdAt: '2026-07-16T00:00:00Z',
    );
  }
}

/// ApiService stub serving a fixed local peers list.
class _MockApiService extends ApiService {
  _MockApiService(this.peers)
    : super(AuthService(), baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> peers;

  @override
  Future<Response> getPeers() async => Response(
    requestOptions: RequestOptions(path: '/api/peers'),
    statusCode: 200,
    data: {'data': peers},
  );
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider(
  List<Map<String, dynamic>> peers,
) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': true,
    'libraryName': 'Test Library',
    'languageCode': 'en',
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    apiService: _MockApiService(peers),
  );
  await provider.loadConfig();
  return (provider, ffi);
}

Map<String, dynamic> _peer({
  required String uuid,
  String status = 'accepted',
}) => {
  'id': 1,
  'name': 'Peer $uuid',
  'url': 'http://192.168.1.99:8000',
  'library_uuid': uuid,
  'connection_status': status,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reconcilePairedPeerFollows (ADR-053)', () {
    test('sends a follow toward an accepted paired peer not yet followed',
        () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('does not re-follow an already followed paired peer', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.following = [
        frb.FrbHubFollow(
          id: 1,
          followerNodeId: _selfNode,
          followedNodeId: _pairedNode,
          status: 'active',
          createdAt: '2026-07-01T00:00:00Z',
        ),
      ];

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
    });

    test('skips pending, placeholder and uuid-less peers', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: 'still-pending', status: 'pending'),
        _peer(uuid: 'peer_42'), // placeholder id, no real uuid handshake yet
        {
          'id': 7,
          'name': 'No uuid',
          'url': 'http://192.168.1.7:8000',
          'connection_status': 'accepted',
        },
        _peer(uuid: _selfNode), // self must never be followed
      ]);

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
      expect(ffi.resolvedFollows, isEmpty);
    });

    test('auto-approves a pending incoming request from a paired peer',
        () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.following = [
        frb.FrbHubFollow(
          id: 1,
          followerNodeId: _selfNode,
          followedNodeId: _pairedNode,
          status: 'active',
          createdAt: '2026-07-01T00:00:00Z',
        ),
      ];
      ffi.pending = [
        frb.FrbHubFollow(
          id: 57,
          followerNodeId: _pairedNode,
          followedNodeId: _selfNode,
          status: 'pending',
          createdAt: '2026-07-16T00:00:00Z',
        ),
        frb.FrbHubFollow(
          id: 58,
          followerNodeId: _strangerNode,
          followedNodeId: _selfNode,
          status: 'pending',
          createdAt: '2026-07-16T00:00:00Z',
        ),
      ];

      await provider.reconcilePairedPeerFollows();

      // The paired peer is approved; the stranger stays pending for the
      // manual approve/reject/block UI.
      expect(ffi.resolvedFollows, [(57, 'approve')]);
      expect(provider.pendingRequests.map((f) => f.id), [58]);
    });

    test('refreshLists: false reuses lists already loaded by the caller',
        () async {
      // The nudge handler refreshes following + pending itself, then calls
      // reconcile with refreshLists: false; reconciliation must act on that
      // state without re-fetching the following list.
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.following = [
        frb.FrbHubFollow(
          id: 1,
          followerNodeId: _selfNode,
          followedNodeId: _pairedNode,
          status: 'active',
          createdAt: '2026-07-01T00:00:00Z',
        ),
      ];
      ffi.pending = [
        frb.FrbHubFollow(
          id: 57,
          followerNodeId: _pairedNode,
          followedNodeId: _selfNode,
          status: 'pending',
          createdAt: '2026-07-16T00:00:00Z',
        ),
      ];
      await provider.loadFollowing();
      await provider.loadPendingRequests();
      final followingCallsBefore = ffi.listFollowingCalls;

      await provider.reconcilePairedPeerFollows(refreshLists: false);

      // Acted on the preloaded state (paired request approved)...
      expect(ffi.resolvedFollows, [(57, 'approve')]);
      // ...without a redundant following re-fetch (the peer is already
      // followed, so neither follow() nor a list refresh should fire).
      expect(ffi.listFollowingCalls, followingCallsBefore);
    });

    test('does not spam follow retries within a session', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);

      await provider.reconcilePairedPeerFollows();
      // Peer has not approved yet: still absent from `following`.
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
    });
  });
}
