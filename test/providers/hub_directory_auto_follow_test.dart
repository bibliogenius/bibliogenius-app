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

  /// When true, the local backend refuses the deletion (500, as the real
  /// `deletePeer` reports any transport or server failure).
  bool deleteFails = false;
  final List<int> deletedPeerIds = [];

  @override
  Future<Response> getPeers() async => Response(
    requestOptions: RequestOptions(path: '/api/peers'),
    statusCode: 200,
    data: {'data': peers},
  );

  @override
  Future<Response> deletePeer(int id) async {
    if (deleteFails) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/$id'),
        statusCode: 500,
        data: {'error': 'refused'},
      );
    }
    deletedPeerIds.add(id);
    peers.removeWhere((p) => p['id'] == id);
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/$id'),
      statusCode: 200,
      data: {'message': 'Peer deleted'},
    );
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider(
  List<Map<String, dynamic>> peers,
) async {
  final (provider, ffi, _) = await _createProviderWithApi(peers);
  return (provider, ffi);
}

Future<(HubDirectoryProvider, _MockFfiService, _MockApiService)>
_createProviderWithApi(List<Map<String, dynamic>> peers) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': true,
    'libraryName': 'Test Library',
    'languageCode': 'en',
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  final api = _MockApiService(peers);
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    apiService: api,
  );
  await provider.loadConfig();
  return (provider, ffi, api);
}

frb.FrbHubFollow _activeFollowOf(String nodeId) => frb.FrbHubFollow(
  id: 1,
  followerNodeId: _selfNode,
  followedNodeId: nodeId,
  status: 'active',
  createdAt: '2026-07-01T00:00:00Z',
);

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

  // The hub follow itself is revoked by the Rust side once the peers row is
  // gone (ADR-053 follow-up); these tests lock what the provider must do
  // around that call.
  group('removePairing (ADR-053 follow-up)', () {
    test('deletes the peer and drops the followed entry at once', () async {
      // A second pairing stays, so the reconciliation runs its full pass.
      final (provider, ffi, api) = await _createProviderWithApi([
        _peer(uuid: _pairedNode),
        {..._peer(uuid: 'other-node'), 'id': 2},
      ]);
      ffi.following = [
        _activeFollowOf(_pairedNode),
        _activeFollowOf('other-node'),
      ];
      await provider.loadFollowing();

      final ok = await provider.removePairing(
        peerId: 1,
        nodeId: _pairedNode,
      );

      expect(ok, isTrue);
      expect(api.deletedPeerIds, [1]);
      expect(provider.following.map((f) => f.followedNodeId), ['other-node']);
      // No refresh: the hub may still list the follow being revoked.
      expect(ffi.listFollowingCalls, 1);
    });

    test('re-arms the auto-follow for a later re-pairing', () async {
      final (provider, ffi, api) = await _createProviderWithApi([
        _peer(uuid: _pairedNode),
      ]);
      await provider.reconcilePairedPeerFollows();
      expect(ffi.followedNodes, [_pairedNode]);

      await provider.removePairing(peerId: 1, nodeId: _pairedNode);
      // Same session: the two devices pair again.
      api.peers.add(_peer(uuid: _pairedNode));
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode, _pairedNode]);
    });

    test('a refused deletion changes nothing', () async {
      final (provider, ffi, api) = await _createProviderWithApi([
        _peer(uuid: _pairedNode),
      ]);
      ffi.following = [_activeFollowOf(_pairedNode)];
      await provider.loadFollowing();
      api.deleteFails = true;

      final ok = await provider.removePairing(
        peerId: 1,
        nodeId: _pairedNode,
      );

      expect(ok, isFalse);
      expect(api.deletedPeerIds, isEmpty);
      expect(provider.following.map((f) => f.followedNodeId), [_pairedNode]);
    });
  });
}
