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
const _hubUrl = 'https://hub.example';

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
  final List<bool> ownerGestures = [];

  /// Active follows the local library already holds.
  List<frb.FrbHubFollow> following = [];

  /// Pending incoming follow requests.
  List<frb.FrbHubFollow> pending = [];

  /// Libraries holding an active follow of the local one.
  List<frb.FrbHubFollow> followers = [];

  /// When set, the hub answers a follow with this error (the core's
  /// rendering of it).
  String? followError;

  /// When true, the hub cannot be read for the followers.
  bool followersUnreadable = false;

  @override
  String? hubEffectiveUrl() => _hubUrl;

  int listFollowingCalls = 0;
  int listFollowersCalls = 0;
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
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async {
    listFollowersCalls++;
    if (followersUnreadable) throw Exception('Network error: unreachable');
    return followers;
  }

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async {
    pendingRequestsCalls++;
    return pending;
  }

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async {
    followedNodes.add(nodeId);
    final error = followError;
    if (error != null) throw Exception(error);
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
    String? followerX25519PublicKey,
    String? followerNodeId,
    required bool ownerGesture,
  }) async {
    resolvedFollows.add((followId, resolution));
    ownerGestures.add(ownerGesture);
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

frb.FrbHubFollow _followFrom(
  String nodeId, {
  required int id,
  required String status,
}) => frb.FrbHubFollow(
  id: id,
  followerNodeId: nodeId,
  followedNodeId: _selfNode,
  status: status,
  createdAt: '2026-07-16T00:00:00Z',
);

/// A local peers row. [onHub] false is a peer paired over the local network
/// that never registered on the hub: its row carries no relay credentials
/// (ADR-073).
Map<String, dynamic> _peer({
  required String uuid,
  String status = 'accepted',
  bool onHub = true,
}) => {
  'id': 1,
  'name': 'Peer $uuid',
  'url': 'http://192.168.1.99:8000',
  'library_uuid': uuid,
  'connection_status': status,
  'relay_url': onHub ? '$_hubUrl/' : null,
  'mailbox_id': onHub ? 'mailbox-$uuid' : null,
  'relay_write_token': onHub ? 'token-$uuid' : null,
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
      // The automatism, not the owner: Rust refuses it for a library whose
      // pairing the owner ended (ADR-072 D4).
      expect(ffi.ownerGestures, [false]);
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

  // ADR-073: a device may decline the hub and pair over the local network
  // only. Its library id must never reach the hub through the follow of a
  // registered peer.
  group('reconcilePairedPeerFollows toward a peer off the hub (ADR-073)', () {
    test('sends no follow toward a paired peer that shows no sign of being '
        'registered', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);

      await provider.reconcilePairedPeerFollows();
      // Every later trigger (launch, pairing, nudge) stays silent too.
      await provider.reconcilePairedPeerFollows();
      await provider.reconcilePairedPeerFollows(refreshLists: false);

      expect(ffi.followedNodes, isEmpty);
    });

    test('incomplete relay credentials are not a sign of registration',
        () async {
      final (provider, ffi) = await _createProvider([
        {
          ..._peer(uuid: _pairedNode, onHub: false),
          'mailbox_id': 'mailbox-without-token',
          'relay_write_token': '',
        },
      ]);

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
    });

    test('a relay mailbox on another hub is not a sign of registration on '
        'ours', () async {
      final (provider, ffi) = await _createProvider([
        {
          ..._peer(uuid: _pairedNode),
          'relay_url': 'https://self-hosted.example',
        },
      ]);

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
    });

    test('stops asking for the session once the hub says the peer is not '
        'registered (credentials outliving a withdrawal)', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.followError = 'Hub error 404: {"error":"Library not found."}';

      await provider.reconcilePairedPeerFollows();
      await provider.reconcilePairedPeerFollows();
      await provider.reconcilePairedPeerFollows(refreshLists: false);

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('asks again after a "not found" when the peer then follows us',
        () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.followError = 'Hub error 404: {"error":"Library not found."}';
      await provider.reconcilePairedPeerFollows();

      // The peer registered again and its request reached us.
      ffi.followError = null;
      ffi.pending = [_followFrom(_pairedNode, id: 57, status: 'pending')];
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode, _pairedNode]);
    });

    test('a transient failure is still retried by the next trigger', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.followError = 'Network error: connection refused';
      await provider.reconcilePairedPeerFollows();

      ffi.followError = null;
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode, _pairedNode]);
    });

    test('a follower that left the hub since the last read is not asked for '
        'on every nudge', () async {
      // It followed us, then withdrew: the hub dropped its profile and our
      // follow of it, but the followers list loaded at launch still has it.
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      ffi.followers = [_followFrom(_pairedNode, id: 57, status: 'active')];
      await provider.loadFollowers();
      ffi.followError = 'Hub error 404: {"error":"Library not found."}';

      await provider.reconcilePairedPeerFollows(refreshLists: false);
      await provider.reconcilePairedPeerFollows(refreshLists: false);
      await provider.reconcilePairedPeerFollows(refreshLists: false);

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('followers that could not be re-read prove nothing', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      ffi.followers = [_followFrom(_pairedNode, id: 57, status: 'active')];
      await provider.loadFollowers();
      ffi.followersUnreadable = true;

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
    });

    test('a nudge does not re-read the followers for a peer off the hub',
        () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      await provider.reconcilePairedPeerFollows();
      final before = ffi.listFollowersCalls;

      await provider.reconcilePairedPeerFollows(refreshLists: false);
      await provider.reconcilePairedPeerFollows(refreshLists: false);

      expect(ffi.listFollowersCalls, before);
      expect(ffi.followedNodes, isEmpty);
    });

    test('follows only the registered one of two paired peers', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
        {..._peer(uuid: 'lan-only-node', onHub: false), 'id': 2},
      ]);

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('follows once the peer registered later and its relay credentials '
        'reached its row', () async {
      final (provider, ffi, api) = await _createProviderWithApi([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      await provider.reconcilePairedPeerFollows();
      expect(ffi.followedNodes, isEmpty);

      // The peer accepted the hub; a local sync refreshed its row.
      api.peers
        ..clear()
        ..add(_peer(uuid: _pairedNode));
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('follows back a peer that registered later and asked to follow us, '
        'before any relay credentials arrive', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      await provider.reconcilePairedPeerFollows();
      expect(ffi.followedNodes, isEmpty);

      // Its request can only come through the hub: the peer is registered.
      ffi.pending = [_followFrom(_pairedNode, id: 57, status: 'pending')];
      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
      expect(ffi.resolvedFollows, [(57, 'approve')]);
    });

    test('follows a peer off the relay that is already one of our followers',
        () async {
      // The request was approved earlier but our own follow never went out
      // (failure, restart): the active follow still proves the registration.
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      ffi.followers = [_followFrom(_pairedNode, id: 57, status: 'active')];

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, [_pairedNode]);
    });

    test('a follow request from a stranger proves nothing about a paired '
        'peer', () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode, onHub: false),
      ]);
      ffi.pending = [_followFrom(_strangerNode, id: 58, status: 'pending')];
      ffi.followers = [_followFrom('other-stranger', id: 59, status: 'active')];

      await provider.reconcilePairedPeerFollows();

      expect(ffi.followedNodes, isEmpty);
      expect(ffi.resolvedFollows, isEmpty);
    });

    test('reads the followers only when a paired peer is left without a sign',
        () async {
      final (provider, ffi) = await _createProvider([
        _peer(uuid: _pairedNode),
      ]);
      // The first pass of a launch reads them for the contact card.
      await provider.reconcilePairedPeerFollows();
      final before = ffi.listFollowersCalls;

      await provider.reconcilePairedPeerFollows();

      expect(ffi.listFollowersCalls, before);
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
