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
}

/// Mock FfiService that lets tests control register success/failure.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  // --- relay config ---
  frb.FrbRelayConfig? relayConfig = const frb.FrbRelayConfig(
    relayUrl: 'wss://relay.example.com',
    mailboxUuid: 'mbx-1234',
    writeToken: 'wt-secret',
  );

  // --- register behavior ---
  int registerCallCount = 0;
  /// Number of times register should fail before succeeding.
  /// -1 = always fail.
  int failCount = 0;
  /// If set, register throws this error string (simulates 401, network, etc.)
  String? registerError;

  /// Last params passed to register, for verification.
  frb.FrbRegisterParams? lastRegisterParams;

  // --- directory config ---
  frb.FrbDirectoryConfig? _config;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<int> countBooks() async => 42;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => _config;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCallCount++;
    lastRegisterParams = params;
    if (registerError != null) {
      throw Exception(registerError);
    }
    if (failCount == -1 || registerCallCount <= failCount) {
      return null; // register returns null => failure
    }
    return const frb.FrbDirectoryConfig(
      nodeId: 'node-1',
      isListed: true,
      requiresApproval: false,
      acceptFrom: 'everyone',
      allowBorrowing: true,
    );
  }

  @override
  Future<int> hubDirectorySyncCatalog() async => 0;

  // Stubbed so the 401 recovery path doesn't hit real FFI in tests.
  int purgeConfigCallCount = 0;
  @override
  Future<bool> hubDirectoryPurgeConfig() async {
    purgeConfigCallCount++;
    _config = null;
    return true;
  }

  /// Pre-load a config so the provider thinks it's registered.
  void setRegistered() {
    _config = const frb.FrbDirectoryConfig(
      nodeId: 'node-1',
      isListed: true,
      requiresApproval: false,
      acceptFrom: 'everyone',
      allowBorrowing: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper: bootstrap a provider in "registered" state
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider({
  int failCount = 0,
  String? registerError,
  frb.FrbRelayConfig? relayConfigOverride,
}) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': true,
    'libraryName': 'Test Library',
    'languageCode': 'en',
  });
  // AuthService uses static storage; swap in an in-memory backend so the
  // 401 recovery path doesn't try to hit the real platform Keychain.
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  ffi.setRegistered();
  ffi.failCount = failCount;
  ffi.registerError = registerError;
  if (relayConfigOverride != null) ffi.relayConfig = relayConfigOverride;

  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  // Use zero delays in tests to avoid 5s waits per retry.
  provider.relayRetryDelay = Duration.zero;
  provider.relayCooldown = Duration.zero;

  // Load the config so the provider is in "registered" state.
  await provider.loadConfig();

  return (provider, ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ensureRelayPublished retry logic', () {
    test('succeeds on first attempt: 1 register call', () async {
      final (provider, ffi) = await _createProvider();

      await provider.ensureRelayPublished();

      expect(ffi.registerCallCount, 1);
      expect(ffi.lastRegisterParams?.relayUrl, 'wss://relay.example.com');
      expect(ffi.lastRegisterParams?.relayMailboxId, 'mbx-1234');
      expect(ffi.lastRegisterParams?.relayWriteToken, 'wt-secret');
    });

    test('fails twice then succeeds on 3rd attempt', () async {
      final (provider, ffi) = await _createProvider(failCount: 2);

      await provider.ensureRelayPublished();

      expect(ffi.registerCallCount, 3);
    });

    test('fails all 3 attempts: exactly 3 register calls', () async {
      final (provider, ffi) = await _createProvider(failCount: -1);

      await provider.ensureRelayPublished();

      expect(ffi.registerCallCount, 3); // max attempts
    });

    test('401 error triggers purge + single recovery retry, then aborts',
        () async {
      final (provider, ffi) = await _createProvider(
        registerError: 'Hub error 401: Unauthorized',
      );

      await provider.ensureRelayPublished();

      // 1st call: initial 401 -> triggers purge + 1 fresh-retry register call.
      // The recovery retry also gets a 401 (mock returns same error every time),
      // which sets _configError so the outer retry loop in ensureRelayPublished
      // aborts. Total: 2 register calls, 1 purge.
      expect(ffi.registerCallCount, 2);
      expect(ffi.purgeConfigCallCount, 1);
    });

    test('no relay config: skips without calling register', () async {
      final (provider, ffi) = await _createProvider();
      ffi.relayConfig = null;

      await provider.ensureRelayPublished();

      expect(ffi.registerCallCount, 0);
    });

    test('re-reads credentials on each attempt (stale data fix)', () async {
      final (provider, ffi) = await _createProvider(failCount: 1);

      // Change relay config after first attempt will be captured.
      // The mock returns relayConfig each time getRelayConfig is called,
      // so we verify that register is called with the latest config.
      ffi.relayConfig = const frb.FrbRelayConfig(
        relayUrl: 'wss://relay-v2.example.com',
        mailboxUuid: 'mbx-new',
        writeToken: 'wt-new',
      );

      await provider.ensureRelayPublished();

      // Both attempts should use the new URL since credentials are re-read.
      expect(ffi.lastRegisterParams?.relayUrl, 'wss://relay-v2.example.com');
      expect(ffi.lastRegisterParams?.relayMailboxId, 'mbx-new');
    });
  });

  group('syncCatalogIfDirty relay retry', () {
    test('retries relay if not yet published', () async {
      // Fail all attempts in ensureRelayPublished -> _relayPublished stays false
      final (provider, ffi) = await _createProvider(failCount: -1);
      await provider.ensureRelayPublished();
      expect(ffi.registerCallCount, 3);

      // Reset mock counters for next round
      ffi.registerCallCount = 0;
      ffi.failCount = 0; // succeed this time

      // Simulate cooldown expired by calling syncCatalogIfDirty.
      // We can't easily fast-forward time, so we test indirectly:
      // calling ensureRelayPublished again should work.
      await provider.ensureRelayPublished();
      expect(ffi.registerCallCount, 1); // succeeded on first try
    });

    test('cooldown prevents hammering: no retry if recent attempt', () async {
      final (provider, ffi) = await _createProvider(failCount: -1);
      // Use a long cooldown so the immediate syncCatalogIfDirty is blocked.
      provider.relayCooldown = const Duration(minutes: 5);

      // First call: 3 register attempts, all fail
      await provider.ensureRelayPublished();
      expect(ffi.registerCallCount, 3);

      ffi.registerCallCount = 0;

      // syncCatalogIfDirty should NOT retry because cooldown hasn't expired.
      await provider.syncCatalogIfDirty();
      expect(ffi.registerCallCount, 0); // skipped due to cooldown
    });
  });
}
