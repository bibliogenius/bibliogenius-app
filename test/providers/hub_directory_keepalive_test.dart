import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.0.0';
}

/// Mock that counts catalog pushes so the keep-alive logic can be observed.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  int syncCatalogCallCount = 0;

  final frb.FrbDirectoryConfig? _config = const frb.FrbDirectoryConfig(
    nodeId: 'node-1',
    isListed: true,
    requiresApproval: false,
    acceptFrom: 'everyone',
    allowBorrowing: true,
  );

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => const frb.FrbRelayConfig(
    relayUrl: 'wss://relay.example.com',
    mailboxUuid: 'mbx-1234',
    writeToken: 'wt-secret',
  );

  @override
  Future<int> countBooks() async => 10;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => null;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => _config;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async => _config;

  @override
  Future<int> hubDirectorySyncCatalog() async {
    syncCatalogCallCount++;
    // 0 ISBNs is still a successful push (>= 0); an empty library must record
    // its push timestamp too, otherwise the keep-alive would loop forever.
    return 0;
  }

  @override
  Future<bool> hubDirectoryPurgeConfig() async => true;
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider() async {
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
  );
  provider.relayRetryDelay = Duration.zero;
  provider.relayCooldown = Duration.zero;

  await provider.loadHubEnabled();
  await provider.loadConfig();
  return (provider, ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('catalog keep-alive', () {
    test('re-pushes an unchanged catalog once it goes stale', () async {
      final (provider, ffi) = await _createProvider();

      // Baseline push: clears the dirty flag and records the push timestamp.
      await provider.syncCatalog();
      expect(ffi.syncCatalogCallCount, 1);
      expect(provider.catalogDirty, false);

      // With a zero threshold the just-recorded push is immediately stale.
      provider.catalogKeepAliveInterval = Duration.zero;
      await provider.syncCatalogIfDirty();

      expect(
        ffi.syncCatalogCallCount,
        2,
        reason: 'a stale unchanged catalog must be re-pushed so the hub TTL '
            'does not prune it and empty the directory fallback',
      );
    });

    test('does not re-push a fresh catalog (no double-push)', () async {
      final (provider, ffi) = await _createProvider();
      provider.catalogKeepAliveInterval = const Duration(days: 365);

      await provider.syncCatalog();
      expect(ffi.syncCatalogCallCount, 1);
      expect(provider.catalogDirty, false);

      await provider.syncCatalogIfDirty();

      expect(
        ffi.syncCatalogCallCount,
        1,
        reason: 'an unchanged, fresh catalog must not be pushed again',
      );
    });

    test('a dirty catalog is pushed regardless of freshness', () async {
      final (provider, ffi) = await _createProvider();
      // Long threshold: only the dirty flag should drive this push.
      provider.catalogKeepAliveInterval = const Duration(days: 365);

      // Fresh providers start dirty (catalog not yet pushed this session).
      expect(provider.catalogDirty, true);

      await provider.syncCatalogIfDirty();
      expect(ffi.syncCatalogCallCount, 1);
      expect(provider.catalogDirty, false);

      // Second lifecycle hook: now clean and fresh, so it must stay quiet.
      await provider.syncCatalogIfDirty();
      expect(ffi.syncCatalogCallCount, 1);
    });
  });
}
