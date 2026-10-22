import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/catalog_push_mode.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _selfNode = 'self-node-uuid';
const _readerNode = 'reader-node-uuid';
const _pairedNode = 'paired-peer-uuid';
const _readerKey = 'abababababababababababababababababababababababababababababababab';

frb.FrbHubFollow _follower({
  required int id,
  required String node,
  String status = 'active',
  String? key = _readerKey,
  String? version = '1.3.0+600',
  String? readerStatus = 'reader',
}) => frb.FrbHubFollow(
  id: id,
  followerNodeId: node,
  followedNodeId: _selfNode,
  status: status,
  createdAt: '2026-10-19T00:00:00Z',
  followerX25519PublicKey: key,
  followerAppVersion: version,
  catalogReaderStatus: readerStatus,
);

/// A hub seen through the FFI: an unlisted library (so the catalog is a
/// candidate for encryption), its followers, and counters for every catalog
/// call the provider can make.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  bool isListed = false;
  bool requiresApproval = true;
  List<frb.FrbHubFollow> followers = [];
  List<frb.FrbHubFollow> pending = [];
  bool failFollowers = false;

  int clearPushes = 0;
  int encryptedPushes = 0;

  /// The Rust side hands out the wraps after the ciphertext; an encrypted
  /// push that cannot deliver them reports a failure.
  bool failEncryptedPush = false;

  /// Every catalog call in order, to pin what happens before what.
  final List<String> events = [];

  /// Every resolution, as (follow_id, resolution, follower key, follower
  /// node id).
  final List<(int, String, String?, String?)> resolved = [];

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      frb.FrbDirectoryConfig(
        nodeId: _selfNode,
        isListed: isListed,
        requiresApproval: requiresApproval,
        acceptFrom: 'everyone',
        allowBorrowing: false,
      );

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 3;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async {
    if (failFollowers) throw Exception('hub unreachable');
    return followers;
  }

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async => const [];

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async =>
      pending;

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async => null;

  @override
  Future<int> hubDirectorySyncCatalog() async {
    clearPushes++;
    events.add('push:clear');
    return 3;
  }

  @override
  Future<int> hubDirectorySyncCatalogEncrypted() async {
    encryptedPushes++;
    events.add('push:encrypted');
    return failEncryptedPush ? -1 : 3;
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
    resolved.add((
      followId,
      resolution,
      followerX25519PublicKey,
      followerNodeId,
    ));
    pending = pending.where((f) => f.id != followId).toList();
    return _follower(id: followId, node: _readerNode);
  }
}

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test';

  @override
  Future<String?> getAppVersion() async => '1.3.0+600';
}

class _MockApiService extends ApiService {
  _MockApiService() : super(AuthService(), baseUrl: 'http://localhost:0');

  @override
  Future<Response> getPeers() async => Response(
    requestOptions: RequestOptions(path: '/api/peers'),
    statusCode: 200,
    data: {'data': const []},
  );

  @override
  Future<Response> deletePeer(int peerId) async => Response(
    requestOptions: RequestOptions(path: '/api/peers/$peerId'),
    statusCode: 204,
  );
}

Future<(HubDirectoryProvider, _MockFfiService)> _provider() async {
  SharedPreferences.setMockInitialValues({'hub_directory_enabled': false});
  AuthService.storage = MockSecureStorage();
  final ffi = _MockFfiService();
  final p = HubDirectoryProvider(
    ffi: ffi,
    apiService: _MockApiService(),
    deviceService: _MockDeviceService(),
  );
  await p.loadHubEnabled();
  await p.loadConfig();
  return (p, ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('syncCatalog push mode (ADR-072 D8)', () {
    test('encrypts when every active follower can read', () async {
      final (p, ffi) = await _provider();
      ffi.followers = [_follower(id: 1, node: _readerNode)];

      final count = await p.syncCatalog();

      expect(count, 3);
      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);
      expect(ffi.encryptedPushes, 1);
      expect(ffi.clearPushes, 0);
    });

    test('an encrypted push whose wraps failed keeps the catalog dirty',
        () async {
      final (p, ffi) = await _provider();
      ffi.followers = [_follower(id: 1, node: _readerNode)];
      ffi.failEncryptedPush = true;

      final count = await p.syncCatalog();

      expect(count, -1);
      expect(p.lastCatalogPushMode, isNull);
      // Still dirty: the lifecycle hook pushes (and wraps) again.
      ffi.failEncryptedPush = false;
      await p.syncCatalogIfDirty();
      expect(ffi.encryptedPushes, 2);
      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);
    });

    test('one reader on an older build keeps the catalog in clear', () async {
      final (p, ffi) = await _provider();
      ffi.followers = [
        _follower(id: 1, node: _readerNode),
        _follower(id: 2, node: _pairedNode, version: '1.2.3+498'),
      ];

      await p.syncCatalog();

      expect(p.lastCatalogPushMode, CatalogPushMode.clear);
      expect(ffi.clearPushes, 1);
      expect(ffi.encryptedPushes, 0);
    });

    test('a public library pushes in clear without reading its followers',
        () async {
      final (p, ffi) = await _provider();
      ffi.isListed = true;
      ffi.requiresApproval = false;
      await p.loadConfig();
      ffi.failFollowers = true;

      await p.syncCatalog();

      expect(p.lastCatalogPushMode, CatalogPushMode.clear);
      expect(ffi.clearPushes, 1);
    });

    test('readers the owner cannot see mean a clear push, never a blind one',
        () async {
      final (p, ffi) = await _provider();
      ffi.failFollowers = true;

      await p.syncCatalog();

      expect(p.lastCatalogPushMode, CatalogPushMode.clear);
      expect(ffi.clearPushes, 1);
      expect(ffi.encryptedPushes, 0);
    });
  });

  group('catalog readers and rotation (ADR-072 D3, D4, R1+)', () {
    test('approving a follow passes its key and node id so Rust can pin and wrap',
        () async {
      final (p, ffi) = await _provider();
      ffi.pending = [
        _follower(id: 7, node: _readerNode, status: 'pending'),
      ];
      await p.loadPendingRequests();

      await p.resolveFollow(7, 'approve', ownerGesture: true);

      expect(ffi.resolved, [(7, 'approve', _readerKey, _readerNode)]);
    });

    test('an ex-peer still following does not keep the catalog in clear',
        () async {
      final (p, ffi) = await _provider();
      ffi.followers = [
        _follower(id: 1, node: _readerNode),
        _follower(
          id: 2,
          node: _pairedNode,
          version: '1.2.3+498',
          readerStatus: 'not_reader',
        ),
      ];

      await p.syncCatalog();

      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);
    });

    test('a reader whose key changed keeps the catalog in clear', () async {
      final (p, ffi) = await _provider();
      ffi.followers = [
        _follower(id: 1, node: _readerNode, readerStatus: 'key_mismatch'),
      ];

      await p.syncCatalog();

      expect(p.lastCatalogPushMode, CatalogPushMode.clear);
    });

    test('a follower that left needs nothing from the app: Rust rotates',
        () async {
      final (p, ffi) = await _provider();
      ffi.followers = [
        _follower(id: 1, node: _readerNode),
        _follower(id: 2, node: _pairedNode),
      ];
      await p.syncCatalog();

      ffi.followers = [_follower(id: 1, node: _readerNode)];
      p.markCatalogDirty();
      await p.syncCatalog();

      expect(ffi.events, ['push:encrypted', 'push:encrypted']);
    });

    test('ending a pairing marks the catalog for a push', () async {
      final (p, ffi) = await _provider();
      ffi.followers = [_follower(id: 1, node: _readerNode)];
      await p.syncCatalog();

      final ok = await p.removePairing(peerId: 4, nodeId: _pairedNode);
      await p.syncCatalogIfDirty();

      expect(ok, isTrue);
      expect(ffi.encryptedPushes, 2);
    });

    test('accepting a pairing marks the catalog for a push', () async {
      // A peer let back in while its follow stayed active gets its wrap
      // from the next push, which must not wait for a book change.
      final (p, ffi) = await _provider();
      ffi.followers = [_follower(id: 1, node: _readerNode)];
      await p.syncCatalog();

      await p.pairingAccepted();
      await p.syncCatalogIfDirty();

      expect(ffi.encryptedPushes, 2);
    });
  });
}
