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
  Future<String?> getAppVersion() async => '1.2.3';
}

/// Mock FFI that captures register() calls so tests can assert the
/// displayName actually pushed to the hub.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  frb.FrbRelayConfig? relayConfig = const frb.FrbRelayConfig(
    relayUrl: 'wss://relay.example.com',
    mailboxUuid: 'mbx-1234',
    writeToken: 'wt-secret',
  );

  /// If non-null, loadConfig() will hydrate the provider with this config.
  frb.FrbDirectoryConfig? existingConfig;

  /// If false, hubDirectoryRegister returns null (simulates hub unreachable).
  bool registerOk = true;

  int registerCallCount = 0;
  final List<frb.FrbRegisterParams> registerParamsLog = [];

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<int> countBooks() async => 42;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      existingConfig;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCallCount++;
    registerParamsLog.add(params);
    if (!registerOk) return null;
    final next = frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed,
      requiresApproval: params.requiresApproval,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing,
    );
    existingConfig = next;
    return next;
  }

  @override
  Future<int> hubDirectorySyncCatalog() async => 0;

  @override
  Future<bool> hubDirectoryPurgeConfig() async => true;

  @override
  Future<String?> hubDirectoryExportWriteToken() async => 'write-token-hex';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider({
  frb.FrbDirectoryConfig? existingConfig,
  bool registerOk = true,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': true,
    'libraryName': 'Bibliothèque de SM-A405FN #JDD8',
    'languageCode': 'fr',
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService()
    ..existingConfig = existingConfig
    ..registerOk = registerOk;

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

frb.FrbDirectoryConfig _config({
  String nodeId = 'node-uuid-1',
  bool isListed = true,
  bool requiresApproval = false,
  String acceptFrom = 'anyone',
  bool allowBorrowing = true,
}) {
  return frb.FrbDirectoryConfig(
    nodeId: nodeId,
    isListed: isListed,
    requiresApproval: requiresApproval,
    acceptFrom: acceptFrom,
    allowBorrowing: allowBorrowing,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('syncDisplayName', () {
    test('pushes the new name to the hub when config is already loaded',
        () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(
          nodeId: '2e69adfd-3f28-43d3-92a5-a22e3e8e2501',
          isListed: true,
          requiresApproval: true,
          acceptFrom: 'mutual',
          allowBorrowing: false,
        ),
      );
      expect(provider.isRegistered, true);
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      final ok = await provider.syncDisplayName('Bibliothèque de Androtest');

      expect(ok, true);
      expect(ffi.registerCallCount, 1);
      final params = ffi.registerParamsLog.single;
      expect(params.nodeId, '2e69adfd-3f28-43d3-92a5-a22e3e8e2501');
      expect(params.displayName, 'Bibliothèque de Androtest');
      // Existing config fields must be preserved across the rename.
      expect(params.isListed, true);
      expect(params.requiresApproval, true);
      expect(params.acceptFrom, 'mutual');
      expect(params.allowBorrowing, false);
      // Device/relay fields included so the hub does not overwrite them.
      expect(params.deviceModel, 'TestDevice');
      expect(params.relayUrl, 'wss://relay.example.com');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_pending_display_name'), isNull,
          reason: 'success must clear any stale pending flag');
    });

    test(
        'triggers silent registration then pushes the name when config is null',
        () async {
      final (provider, ffi) = await _createProvider();
      expect(provider.isRegistered, false, reason: 'baseline: no config');

      final ok = await provider.syncDisplayName('Bibliothèque de Androtest');

      expect(ok, true);
      // At least two register() calls: one from _ensureSilentRegistration,
      // one from the follow-up _pushDisplayName with the user-picked name.
      expect(ffi.registerCallCount, greaterThanOrEqualTo(2));
      expect(
        ffi.registerParamsLog.last.displayName,
        'Bibliothèque de Androtest',
        reason: 'last register() must carry the renamed library name',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_pending_display_name'), isNull);
    });

    test('stores a pending flag when the hub push fails', () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(),
        registerOk: false,
      );
      ffi.registerCallCount = 0;

      final ok = await provider.syncDisplayName('Bibliothèque de Androtest');

      expect(ok, false);
      expect(ffi.registerCallCount, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_display_name'),
        'Bibliothèque de Androtest',
        reason:
            'failed hub push must persist the desired name for replay on next sync',
      );
    });

    test('stores a pending flag when silent registration cannot create config',
        () async {
      final (provider, ffi) = await _createProvider(registerOk: false);
      ffi.registerCallCount = 0;

      final ok = await provider.syncDisplayName('Bibliothèque de Androtest');

      expect(ok, false);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_display_name'),
        'Bibliothèque de Androtest',
      );
    });

    test('ignores blank input without touching the hub', () async {
      final (provider, ffi) =
          await _createProvider(existingConfig: _config());
      ffi.registerCallCount = 0;

      final ok = await provider.syncDisplayName('   ');

      expect(ok, false);
      expect(ffi.registerCallCount, 0);
    });
  });

  group('pending displayName replay', () {
    test('initAndSyncCatalog consumes the pending flag and pushes to hub',
        () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(nodeId: 'node-uuid-1'),
        prefs: const {
          'hub_pending_display_name': 'Bibliothèque de Androtest',
        },
      );
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      await provider.initAndSyncCatalog();

      // ensureRelayPublished may call register too; what matters is that at
      // least one call carries the pending name and that the flag is cleared.
      final renamedCalls = ffi.registerParamsLog
          .where((p) => p.displayName == 'Bibliothèque de Androtest')
          .toList();
      expect(renamedCalls, isNotEmpty,
          reason: 'pending displayName must be replayed to the hub');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_pending_display_name'), isNull,
          reason: 'successful replay must clear the pending flag');
    });

    test('leaves the pending flag in place when the hub is still unreachable',
        () async {
      final (provider, _) = await _createProvider(
        existingConfig: _config(),
        registerOk: false,
        prefs: const {
          'hub_pending_display_name': 'Bibliothèque de Androtest',
        },
      );

      await provider.initAndSyncCatalog();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_display_name'),
        'Bibliothèque de Androtest',
        reason: 'failed replay must keep the flag so a later cycle retries',
      );
    });
  });
}
