import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/contact_audience.dart';
import 'package:bibliogenius/models/hub_directory.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _selfNode = 'self-node-uuid';
const _pairedNode = 'paired-peer-uuid';
const _strangerNode = 'stranger-node-uuid';
const _card = '{"v":1,"email":"owner@example.org"}';

frb.FrbHubFollow _follower({
  required int id,
  required String node,
  String status = 'active',
  String? key = 'aa',
  String? blob,
}) => frb.FrbHubFollow(
  id: id,
  followerNodeId: node,
  followedNodeId: _selfNode,
  status: status,
  createdAt: '2026-09-29T00:00:00Z',
  encryptedContact: blob,
  followerX25519PublicKey: key,
);

HubFollow _hf({
  required int id,
  required String node,
  String status = 'active',
  String? key = 'aa',
  String? blob,
}) => HubFollow.fromFrb(
  _follower(id: id, node: node, status: status, key: key, blob: blob),
);

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  List<frb.FrbHubFollow> followers = [];
  List<frb.FrbHubFollow> following = [];
  List<frb.FrbHubFollow> pending = [];

  /// Every `contacts/sync` push, as (follow_id -> blob).
  final List<Map<int, String>> syncPushes = [];

  /// Every resolution, as (follow_id, resolution, blob).
  final List<(int, String, String?)> resolved = [];

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      const frb.FrbDirectoryConfig(
        nodeId: _selfNode,
        isListed: false,
        requiresApproval: true,
        acceptFrom: 'everyone',
        allowBorrowing: false,
      );

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => followers;

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async => following;

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async => pending;

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async => null;

  @override
  Future<String> sealBlob(String recipientX25519Hex, String plaintext) async =>
      'sealed-for-$recipientX25519Hex';

  @override
  Future<String> openBlob(String sealedBase64) async => _card;

  @override
  Future<int> hubDirectorySyncContacts(
    List<int> followIds,
    List<String> encryptedContacts,
  ) async {
    syncPushes.add(Map.fromIterables(followIds, encryptedContacts));
    return followIds.length;
  }

  @override
  Future<frb.FrbHubFollow?> hubDirectoryResolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
  }) async {
    resolved.add((followId, resolution, encryptedContact));
    pending = pending.where((f) => f.id != followId).toList();
    return _follower(id: followId, node: _pairedNode);
  }
}

class _MockApiService extends ApiService {
  _MockApiService(this.peers)
    : super(AuthService(), baseUrl: 'http://localhost:0');

  List<Map<String, dynamic>> peers;

  @override
  Future<Response> getPeers() async => Response(
    requestOptions: RequestOptions(path: '/api/peers'),
    statusCode: 200,
    data: {'data': peers},
  );
}

Map<String, dynamic> _peer(String uuid) => {
  'id': 1,
  'name': 'Peer $uuid',
  'url': 'http://192.168.1.99:8000',
  'library_uuid': uuid,
  'connection_status': 'accepted',
};

Future<(HubDirectoryProvider, _MockFfiService, _MockApiService)> _provider({
  Map<String, Object> prefs = const {},
  List<String> paired = const [_pairedNode],
  bool hubEnabled = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': hubEnabled,
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();
  final ffi = _MockFfiService();
  final api = _MockApiService(paired.map(_peer).toList());
  final p = HubDirectoryProvider(ffi: ffi, apiService: api);
  await p.loadHubEnabled();
  await p.loadConfig();
  await p.loadContactInfo();
  return (p, ffi, api);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planContactSync', () {
    final paired = {_pairedNode};

    test('a paired peer is sealed for with the paired audience', () {
      final plan = planContactSync(
        followers: [_hf(id: 1, node: _pairedNode)],
        pairedUuids: paired,
        audience: ContactAudience.fresh,
        hasCard: true,
      );
      expect(plan.seal.map((f) => f.id), [1]);
      expect(plan.clear, isEmpty);
    });

    test('a directory follower is sealed for only when ticked', () {
      final followers = [_hf(id: 2, node: _strangerNode)];
      final off = planContactSync(
        followers: followers,
        pairedUuids: paired,
        audience: ContactAudience.fresh,
        hasCard: true,
      );
      expect(off.seal, isEmpty);

      final on = planContactSync(
        followers: followers,
        pairedUuids: paired,
        audience: ContactAudience.legacy,
        hasCard: true,
      );
      expect(on.seal.map((f) => f.id), [2]);
    });

    test('an excluded follower holding a blob is cleared', () {
      final plan = planContactSync(
        followers: [
          _hf(id: 1, node: _pairedNode, blob: 'old'),
          _hf(id: 2, node: _strangerNode, blob: 'old'),
        ],
        pairedUuids: paired,
        audience: const ContactAudience(
          pairedPeers: false,
          directoryFollowers: false,
        ),
        hasCard: true,
      );
      expect(plan.seal, isEmpty);
      expect(plan.clear.map((f) => f.id), [1, 2]);
    });

    test('an excluded follower holding nothing is left alone', () {
      final plan = planContactSync(
        followers: [_hf(id: 2, node: _strangerNode)],
        pairedUuids: paired,
        audience: ContactAudience.fresh,
        hasCard: true,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('an emptied card is cleared from every follower', () {
      final plan = planContactSync(
        followers: [
          _hf(id: 1, node: _pairedNode, blob: 'old'),
          _hf(id: 2, node: _strangerNode, blob: 'old'),
        ],
        pairedUuids: paired,
        audience: ContactAudience.legacy,
        hasCard: false,
      );
      expect(plan.seal, isEmpty);
      expect(plan.clear.map((f) => f.id), [1, 2]);
    });

    test('pending followers are never touched', () {
      final plan = planContactSync(
        followers: [
          _hf(id: 1, node: _pairedNode, status: 'pending'),
          _hf(id: 2, node: _strangerNode, status: 'pending', blob: 'old'),
        ],
        pairedUuids: paired,
        audience: ContactAudience.legacy,
        hasCard: true,
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('ContactAudience storage', () {
    test('round-trips through its string form', () {
      for (final a in const [
        ContactAudience(pairedPeers: true, directoryFollowers: true),
        ContactAudience(pairedPeers: true, directoryFollowers: false),
        ContactAudience(pairedPeers: false, directoryFollowers: true),
        ContactAudience(pairedPeers: false, directoryFollowers: false),
      ]) {
        expect(ContactAudience.decode(a.encode()), a);
      }
    });
  });

  group('audience defaults on load', () {
    test('no card yet: paired peers only', () async {
      final (p, _, _) = await _provider();
      expect(p.contactAudience, ContactAudience.fresh);
    });

    test('an existing card keeps both audiences', () async {
      final (p, _, _) = await _provider(prefs: {'hub_contact_info': _card});
      expect(p.contactAudience, ContactAudience.legacy);
    });

    test('the default is persisted once, then never recomputed', () async {
      final (p, _, _) = await _provider(prefs: {'hub_contact_info': _card});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_contact_audience'), 'paired,directory');

      // Emptying the card later must not flip the audience to the fresh
      // default on the next load.
      await p.setContactCard(p.contactCard.copyWith(email: ''));
      await p.loadContactInfo();
      expect(p.contactAudience, ContactAudience.legacy);
    });

    test('a stored choice wins over the defaults', () async {
      final (p, _, _) = await _provider(
        prefs: {'hub_contact_info': _card, 'hub_contact_audience': ''},
      );
      expect(
        p.contactAudience,
        const ContactAudience(pairedPeers: false, directoryFollowers: false),
      );
    });
  });

  group('syncContactToFollowers', () {
    test('seals for the audience and clears the excluded', () async {
      final (p, ffi, _) = await _provider(
        prefs: {'hub_contact_info': _card, 'hub_contact_audience': 'paired'},
      );
      ffi.followers = [
        _follower(id: 1, node: _pairedNode, key: 'k1'),
        _follower(id: 2, node: _strangerNode, key: 'k2', blob: 'old'),
      ];

      await p.syncContactToFollowers();

      expect(ffi.syncPushes, [
        {1: 'sealed-for-k1', 2: ''},
      ]);
    });

    test('an emptied card is withdrawn from every follower', () async {
      final (p, ffi, _) = await _provider(prefs: {'hub_contact_info': ''});
      ffi.followers = [
        _follower(id: 1, node: _pairedNode, blob: 'old'),
        _follower(id: 2, node: _strangerNode, blob: 'old'),
      ];

      await p.syncContactToFollowers();

      expect(ffi.syncPushes, [
        {1: '', 2: ''},
      ]);
    });

    test('nothing to change: no request at all', () async {
      final (p, ffi, _) = await _provider(prefs: {'hub_contact_info': ''});
      ffi.followers = [_follower(id: 2, node: _strangerNode)];

      await p.syncContactToFollowers();

      expect(ffi.syncPushes, isEmpty);
    });

    test('unticking an audience re-seals and withdraws', () async {
      final (p, ffi, _) = await _provider(prefs: {'hub_contact_info': _card});
      ffi.followers = [
        _follower(id: 1, node: _pairedNode, key: 'k1', blob: 'old'),
        _follower(id: 2, node: _strangerNode, key: 'k2', blob: 'old'),
      ];

      await p.setContactAudience(
        p.contactAudience.copyWith(directoryFollowers: false),
      );

      expect(ffi.syncPushes.last, {1: 'sealed-for-k1', 2: ''});
    });
  });

  group('sealing at approval', () {
    test('a paired peer gets the card', () async {
      final (p, _, _) = await _provider(prefs: {'hub_contact_info': _card});
      final blob = await p.contactBlobForApproval(
        _hf(id: 5, node: _pairedNode, status: 'pending', key: 'k5'),
      );
      expect(blob, 'sealed-for-k5');
    });

    test('a directory follower gets nothing when unticked', () async {
      final (p, _, _) = await _provider(
        prefs: {'hub_contact_info': _card, 'hub_contact_audience': 'paired'},
      );
      final blob = await p.contactBlobForApproval(
        _hf(id: 6, node: _strangerNode, status: 'pending', key: 'k6'),
      );
      expect(blob, isNull);
    });

    test('ADR-053 auto-approval honors the paired audience', () async {
      final (p, ffi, _) = await _provider(
        prefs: {'hub_contact_info': _card, 'hub_contact_audience': ''},
      );
      ffi.following = [
        _follower(id: 1, node: _selfNode).copyWithFollowed(_pairedNode),
      ];
      ffi.pending = [
        _follower(id: 57, node: _pairedNode, status: 'pending', key: 'k57'),
      ];

      await p.reconcilePairedPeerFollows();

      // Still approved (catalog access is ADR-053's point), but without the
      // card: the owner unticked paired peers.
      expect(ffi.resolved, [(57, 'approve', null)]);
    });
  });

  group('re-seal on pairing changes', () {
    test('reconciliation re-projects once, then only on change', () async {
      final (p, ffi, api) = await _provider(
        prefs: {'hub_contact_info': _card, 'hub_contact_audience': 'paired'},
      );
      ffi.followers = [
        _follower(id: 1, node: _pairedNode, key: 'k1'),
        _follower(id: 2, node: _strangerNode, key: 'k2'),
      ];

      await p.reconcilePairedPeerFollows();
      expect(ffi.syncPushes, [
        {1: 'sealed-for-k1'},
      ]);

      await p.reconcilePairedPeerFollows();
      expect(ffi.syncPushes, hasLength(1), reason: 'same paired set');

      // The pairing is removed: the former peer is now a mere follower.
      api.peers = [];
      ffi.followers = [
        _follower(id: 1, node: _pairedNode, key: 'k1', blob: 'old'),
        _follower(id: 2, node: _strangerNode, key: 'k2'),
      ];
      await p.reconcilePairedPeerFollows();
      expect(ffi.syncPushes.last, {1: ''});
    });
  });

  group('reading a peer card', () {
    test('works with the directory switched off', () async {
      final (p, ffi, _) = await _provider(hubEnabled: false);
      ffi.following = [
        frb.FrbHubFollow(
          id: 9,
          followerNodeId: _selfNode,
          followedNodeId: _pairedNode,
          status: 'active',
          createdAt: '2026-09-29T00:00:00Z',
          encryptedContact: 'sealed',
        ),
      ];
      await p.loadFollowing();

      final card = await p.loadContactCardFor(_pairedNode);

      expect(p.isHubEnabled, isFalse);
      expect(card?.email, 'owner@example.org');
    });

    test('an empty blob reads as no card', () async {
      final (p, ffi, _) = await _provider();
      ffi.following = [
        frb.FrbHubFollow(
          id: 9,
          followerNodeId: _selfNode,
          followedNodeId: _pairedNode,
          status: 'active',
          createdAt: '2026-09-29T00:00:00Z',
          encryptedContact: '',
        ),
      ];
      await p.loadFollowing();

      expect(await p.loadContactCardFor(_pairedNode), isNull);
    });
  });
}

extension on frb.FrbHubFollow {
  frb.FrbHubFollow copyWithFollowed(String followed) => frb.FrbHubFollow(
    id: id,
    followerNodeId: followerNodeId,
    followedNodeId: followed,
    status: status,
    createdAt: createdAt,
  );
}
