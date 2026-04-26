import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks (mirror of hub_directory_country_test.dart)
// ---------------------------------------------------------------------------

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.2.3';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  frb.FrbRelayConfig? relayConfig = const frb.FrbRelayConfig(
    relayUrl: 'wss://relay.example.com',
    mailboxUuid: 'mbx-1234',
    writeToken: 'wt-secret',
  );

  frb.FrbDirectoryConfig? existingConfig;

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
  await provider.loadShareCity();
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
  group('shareCity toggle', () {
    test('defaults to false even when the directory toggle is enabled',
        () async {
      final (provider, _) = await _createProvider();
      expect(provider.isShareCityEnabled, false,
          reason:
              'ADR-035 §3: city sharing must be opt-in independently of '
              '"is_listed". Default OFF, including for already-listed users.');
    });

    test('persists across reloads', () async {
      final (provider, _) = await _createProvider();
      await provider.setShareCity(true);
      expect(provider.isShareCityEnabled, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hub_share_city'), true);
    });

    test('setShareCity does NOT push to the hub on its own', () async {
      final (provider, ffi) =
          await _createProvider(existingConfig: _config());
      ffi.registerCallCount = 0;
      await provider.setShareCity(true);
      expect(ffi.registerCallCount, 0,
          reason:
              'Persisting the toggle is cheap and offline-safe; the hub '
              'mirror is the caller\'s responsibility (syncLocationCityId).');
    });
  });

  group('syncLocationCityId', () {
    test('pushes the new city id to the hub when config is already loaded',
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
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      final ok = await provider.syncLocationCityId(2988507); // Paris

      expect(ok, true);
      expect(ffi.registerCallCount, 1);
      final params = ffi.registerParamsLog.single;
      expect(params.locationCityId, 2988507);
      // Existing config fields must be preserved across the city change.
      expect(params.isListed, true);
      expect(params.requiresApproval, true);
      expect(params.acceptFrom, 'mutual');
      expect(params.allowBorrowing, false);
      expect(params.displayName, 'Bibliothèque de SM-A405FN #JDD8');
      // Device/relay fields included so the hub does not blank them.
      expect(params.deviceModel, 'TestDevice');
      expect(params.relayUrl, 'wss://relay.example.com');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), false,
          reason: 'success must clear any stale pending flag');
    });

    test('null clears the city on the hub (toggle off case)', () async {
      final (provider, ffi) =
          await _createProvider(existingConfig: _config());
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      final ok = await provider.syncLocationCityId(null);

      expect(ok, true);
      expect(ffi.registerCallCount, 1);
      expect(ffi.registerParamsLog.single.locationCityId, isNull,
          reason:
              'A null payload is the explicit "stop sharing my city" intent - '
              'the hub mirrors it by setting location_city_id NULL.');
    });

    test('triggers silent registration then pushes the city when config is null',
        () async {
      final (provider, ffi) = await _createProvider();
      expect(provider.isRegistered, false, reason: 'baseline: no config');

      final ok = await provider.syncLocationCityId(2988507);

      expect(ok, true);
      expect(ffi.registerCallCount, greaterThanOrEqualTo(2));
      expect(
        ffi.registerParamsLog.last.locationCityId,
        2988507,
        reason: 'last register() must carry the picked city id',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), false);
    });

    test('stores a pending flag when the hub push fails', () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(),
        registerOk: false,
      );
      ffi.registerCallCount = 0;

      final ok = await provider.syncLocationCityId(2988507);

      expect(ok, false);
      expect(ffi.registerCallCount, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_location_city_id'),
        '2988507',
        reason:
            'failed hub push must persist the desired city id for replay on '
            'next sync',
      );
    });

    test('stores an empty-string sentinel when a clear push fails', () async {
      final (provider, _) = await _createProvider(
        existingConfig: _config(),
        registerOk: false,
      );

      await provider.syncLocationCityId(null);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_location_city_id'),
        '',
        reason:
            'pending "clear my city" must round-trip distinctly from a '
            'pending set, so replay knows to push NULL on the next sync',
      );
    });

    test('stores a pending flag when silent registration cannot create config',
        () async {
      final (provider, ffi) = await _createProvider(registerOk: false);
      ffi.registerCallCount = 0;

      final ok = await provider.syncLocationCityId(2988507);

      expect(ok, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_pending_location_city_id'), '2988507');
    });
  });

  group('pending locationCityId replay', () {
    test('initAndSyncCatalog consumes a pending set and pushes to hub',
        () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(nodeId: 'node-uuid-1'),
        prefs: const {
          'hub_pending_location_city_id': '2988507',
        },
      );
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      await provider.initAndSyncCatalog();

      final cityCalls = ffi.registerParamsLog
          .where((p) => p.locationCityId == 2988507)
          .toList();
      expect(cityCalls, isNotEmpty,
          reason: 'pending locationCityId must be replayed to the hub');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), false,
          reason: 'successful replay must clear the pending flag');
    });

    test('initAndSyncCatalog consumes a pending clear and pushes NULL',
        () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(nodeId: 'node-uuid-1'),
        prefs: const {
          'hub_pending_location_city_id': '',
        },
      );
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      await provider.initAndSyncCatalog();

      // The replay must touch the hub at least once with locationCityId=null.
      final clearCalls = ffi.registerParamsLog
          .where((p) => p.locationCityId == null)
          .toList();
      expect(clearCalls, isNotEmpty,
          reason:
              'pending clear (empty-string sentinel) must replay as a '
              'register() with locationCityId=null');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), false);
    });

    test('leaves the pending flag in place when the hub is still unreachable',
        () async {
      final (provider, _) = await _createProvider(
        existingConfig: _config(),
        registerOk: false,
        prefs: const {
          'hub_pending_location_city_id': '2988507',
        },
      );

      await provider.initAndSyncCatalog();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_location_city_id'),
        '2988507',
        reason: 'failed replay must keep the flag so a later cycle retries',
      );
    });

    test('drops a corrupt pending value instead of looping on it', () async {
      final (provider, ffi) = await _createProvider(
        existingConfig: _config(),
        prefs: const {
          'hub_pending_location_city_id': 'not-a-number',
        },
      );
      ffi.registerCallCount = 0;
      ffi.registerParamsLog.clear();

      await provider.initAndSyncCatalog();

      // No city id should be pushed for the corrupt value.
      final cityIdCalls = ffi.registerParamsLog
          .where((p) => p.locationCityId != null)
          .toList();
      expect(cityIdCalls, isEmpty,
          reason: 'corrupt pending value must not produce a hub call');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), false,
          reason: 'corrupt pending value must be removed, not retried forever');
    });
  });

  group('initAndSyncCatalog loads local city UI state', () {
    // Cold-start guard: a user who already opted into share-city in a
    // previous session must see the right state when the network screen
    // builds before they ever open settings. Without provider-side
    // eager-load, isShareCityEnabled defaulted to false and the empty-
    // state CTA wrongly invited a redundant opt-in.

    test('reads hub_share_city + hub_local_location_city_id from prefs',
        () async {
      SharedPreferences.setMockInitialValues({
        'hub_directory_enabled': true,
        'libraryName': 'TestLib',
        'languageCode': 'en',
        'hub_share_city': true,
        'hub_local_location_city_id': 2988507,
      });
      AuthService.storage = MockSecureStorage();

      // Build a raw provider WITHOUT the _createProvider pre-loads, so
      // the only thing populating UI state is initAndSyncCatalog.
      final ffi = _MockFfiService()..existingConfig = _config();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      )
        ..relayRetryDelay = Duration.zero
        ..relayCooldown = Duration.zero;

      // Pre-conditions: defaults until init runs.
      expect(provider.isShareCityEnabled, false);
      expect(provider.localCityId, null);

      await provider.initAndSyncCatalog();

      expect(provider.isShareCityEnabled, true,
          reason:
              'initAndSyncCatalog must hydrate the share-city toggle so '
              'consumers reading from the provider on cold start see the '
              'persisted value, not the default false.');
      expect(provider.localCityId, 2988507,
          reason: 'same hydration must apply to the locally picked city id');
    });
  });
}
