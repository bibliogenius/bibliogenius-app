import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/catalog_push_mode.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

const _selfNode = 'self-node-uuid';
const _readerNode = 'reader-node-uuid';

/// A hub that applies the visibility flags a registration carries and keeps
/// its values for the flags left out, like the real one (isset).
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  bool isListed = true;
  bool requiresApproval = false;
  bool allowBorrowing = false;
  int clearPushes = 0;
  int encryptedPushes = 0;

  /// Holds every push until completed, to observe overlapping pushes.
  Completer<void>? hold;
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<int> _push() async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await hold?.future;
      return 3;
    } finally {
      _inFlight--;
    }
  }

  frb.FrbDirectoryConfig _config() => frb.FrbDirectoryConfig(
    nodeId: _selfNode,
    isListed: isListed,
    requiresApproval: requiresApproval,
    acceptFrom: 'everyone',
    allowBorrowing: allowBorrowing,
  );

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => _config();

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    isListed = params.isListed ?? isListed;
    requiresApproval = params.requiresApproval ?? requiresApproval;
    allowBorrowing = params.allowBorrowing ?? allowBorrowing;
    return _config();
  }

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 3;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => null;

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => [
    frb.FrbHubFollow(
      id: 1,
      followerNodeId: _readerNode,
      followedNodeId: _selfNode,
      status: 'active',
      createdAt: '2026-10-19T00:00:00Z',
      followerX25519PublicKey:
          'abababababababababababababababababababababababababababababababab',
      followerAppVersion: '1.3.0+600',
    ),
  ];

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async => const [];

  @override
  Future<int> hubDirectorySyncCatalog() async {
    clearPushes++;
    return _push();
  }

  @override
  Future<int> hubDirectorySyncCatalogEncrypted() async {
    encryptedPushes++;
    return _push();
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

Future<(HubDirectoryProvider, _MockFfiService)> _publicLibraryInSync() async {
  SharedPreferences.setMockInitialValues({'hub_directory_enabled': true});
  AuthService.storage = MockSecureStorage();
  final ffi = _MockFfiService();
  final p = HubDirectoryProvider(
    ffi: ffi,
    apiService: ApiService(AuthService(), baseUrl: 'http://localhost:0'),
    deviceService: _MockDeviceService(),
  );
  await p.loadHubEnabled();
  await p.loadConfig();
  // Public library, catalog already on the hub in clear.
  await p.syncCatalog();
  expect(p.lastCatalogPushMode, CatalogPushMode.clear);
  expect(p.catalogDirty, isFalse);
  return (p, ffi);
}

/// Lets the pushes started without being awaited run to completion.
Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _register(
  HubDirectoryProvider p, {
  bool? isListed,
  bool? requiresApproval,
  bool? allowBorrowing,
}) => p.register(
  nodeId: _selfNode,
  displayName: 'Test library',
  bookCount: 3,
  isListed: isListed,
  requiresApproval: requiresApproval,
  acceptFrom: 'everyone',
  allowBorrowing: allowBorrowing,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a visibility change re-pushes the catalog in the new mode', () {
    test('leaving the directory replaces the clear copy right away', () async {
      final (p, ffi) = await _publicLibraryInSync();

      expect(await _register(p, isListed: false), isTrue);
      await _settle();

      // No 5-second debounce: the clear copy must not linger on the hub.
      expect(ffi.encryptedPushes, 1);
      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);
      expect(p.catalogDirty, isFalse);
    });

    test('requiring approval replaces the clear copy right away', () async {
      final (p, ffi) = await _publicLibraryInSync();

      expect(await _register(p, requiresApproval: true), isTrue);
      await _settle();

      expect(ffi.encryptedPushes, 1);
    });

    test('becoming public pushes the catalog in clear', () async {
      final (p, ffi) = await _publicLibraryInSync();
      await _register(p, requiresApproval: true);
      await _settle();
      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);

      await _register(p, requiresApproval: false);
      await _settle();

      expect(ffi.clearPushes, 2);
      expect(p.lastCatalogPushMode, CatalogPushMode.clear);
    });

    test('a registration that keeps the visibility does not re-push',
        () async {
      final (p, ffi) = await _publicLibraryInSync();

      await _register(p);
      await _register(p, allowBorrowing: true);
      await _settle();

      expect(p.catalogDirty, isFalse);
      expect(ffi.clearPushes, 1);
    });
  });

  group('catalog pushes never overlap', () {
    test('a caller that pushes after a visibility change waits its turn',
        () async {
      final (p, ffi) = await _publicLibraryInSync();
      ffi.hold = Completer<void>();

      // The settings and publish flows push themselves after registering.
      await _register(p, isListed: false);
      final callerPush = p.syncCatalog();
      final debounced = p.syncCatalogIfDirty();
      await _settle();
      ffi.hold!.complete();
      await callerPush;
      await debounced;
      await _settle();

      expect(ffi.maxInFlight, 1);
      expect(p.lastCatalogPushMode, CatalogPushMode.encrypted);
    });

    test('calls made during a push share a single rerun', () async {
      final (p, ffi) = await _publicLibraryInSync();
      ffi.hold = Completer<void>();
      final before = ffi.clearPushes;

      final first = p.syncCatalog();
      await _settle();
      final second = p.syncCatalog();
      final third = p.syncCatalog();
      ffi.hold!.complete();
      expect(await first, 3);
      expect(await second, 3);
      expect(await third, 3);

      expect(ffi.maxInFlight, 1);
      expect(ffi.clearPushes - before, 2, reason: 'the push, then one rerun');
    });
  });
}
