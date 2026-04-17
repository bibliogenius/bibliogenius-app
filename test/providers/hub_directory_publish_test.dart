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

/// Minimal mock that verifies the parameters `enableAndPublish` sends to the
/// hub (isListed=true, display name, relay creds) and that catalog push is
/// triggered on success.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  frb.FrbRelayConfig? relayConfig = const frb.FrbRelayConfig(
    relayUrl: 'wss://relay.example.com',
    mailboxUuid: 'mbx-1234',
    writeToken: 'wt-secret',
  );

  int registerCallCount = 0;
  frb.FrbRegisterParams? lastRegisterParams;
  int syncCatalogCallCount = 0;

  /// If true, hubDirectoryRegister returns a success config. If false, null.
  bool registerOk = true;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<int> countBooks() async => 42;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => null;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCallCount++;
    lastRegisterParams = params;
    if (!registerOk) return null;
    return frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed,
      requiresApproval: params.requiresApproval,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing,
    );
  }

  @override
  Future<int> hubDirectorySyncCatalog() async {
    syncCatalogCallCount++;
    return 0;
  }

  @override
  Future<bool> hubDirectoryPurgeConfig() async => true;

  @override
  Future<String?> hubDirectoryExportWriteToken() async => 'write-token-hex';
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider({
  bool registerOk = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': false,
    'libraryName': 'Test Library',
    'languageCode': 'en',
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  ffi.registerOk = registerOk;

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
  group('enableAndPublish', () {
    test('flips _hubEnabled, registers with isListed=true, pushes catalog',
        () async {
      final (provider, ffi) = await _createProvider();
      expect(provider.isHubEnabled, false, reason: 'baseline: hub is off');
      expect(provider.isRegistered, false, reason: 'baseline: no config');

      final ok = await provider.enableAndPublish(
        displayName: 'My Shiny Library',
        locationCountry: 'FR',
      );

      expect(ok, true);
      expect(provider.isHubEnabled, true,
          reason: '_hubEnabled must be true after publish');
      expect(provider.isListed, true,
          reason: 'config.isListed must be true after publish');
      expect(ffi.registerCallCount, 1);
      expect(ffi.lastRegisterParams?.isListed, true);
      expect(ffi.lastRegisterParams?.displayName, 'My Shiny Library');
      expect(ffi.lastRegisterParams?.locationCountry, 'FR');
      expect(ffi.lastRegisterParams?.relayUrl, 'wss://relay.example.com');
      // Privacy-first defaults on first publish: followers need approval
      // before reading the catalog, and physical-loan requests are opt-in.
      expect(ffi.lastRegisterParams?.requiresApproval, true,
          reason: 'first publish must require follower approval by default');
      expect(ffi.lastRegisterParams?.allowBorrowing, false,
          reason: 'first publish must NOT auto-accept borrow requests');
      expect(ffi.syncCatalogCallCount, 1,
          reason: 'catalog must be pushed on success so followers see books');
    });

    test('blank locationCountry is forwarded as null (hub treats "" invalid)',
        () async {
      final (provider, ffi) = await _createProvider();

      await provider.enableAndPublish(
        displayName: 'Lib',
        locationCountry: '   ',
      );

      expect(ffi.lastRegisterParams?.locationCountry, isNull);
    });

    test('register failure still flips _hubEnabled but skips catalog push',
        () async {
      final (provider, ffi) = await _createProvider(registerOk: false);

      final ok = await provider.enableAndPublish(displayName: 'Lib');

      expect(ok, false);
      expect(provider.isHubEnabled, true,
          reason: 'user intent is saved locally even if hub call fails');
      expect(ffi.syncCatalogCallCount, 0,
          reason: 'no catalog push if registration failed');
    });
  });
}
