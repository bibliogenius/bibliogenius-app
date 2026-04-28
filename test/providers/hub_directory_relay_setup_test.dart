import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test';

  @override
  Future<String?> getAppVersion() async => '1.0.0';
}

/// FFI mock that simulates a registered library with NO local relay
/// configuration. Drives the [ensureRelayPublished] entry into the new
/// auto-setup branch added for point 5 of the 2026-04-28 audit.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// Initially null so the provider sees "no local relay config" and
  /// triggers the auto-setup. After [_MockApiService.setupRelay] returns
  /// a successful response, tests can flip this to a populated config to
  /// simulate the FFI-side persistence step.
  frb.FrbRelayConfig? relayConfig;

  int registerCallCount = 0;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<int> countBooks() async => 7;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCallCount++;
    return frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed,
      requiresApproval: params.requiresApproval,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing,
    );
  }
}

/// ApiService stub that captures [setupRelay] invocations without touching
/// Dio. Returning a successful response also flips the FFI mock's relay
/// config so the second [_getRelayCredentials] read in the provider sees
/// freshly persisted creds, mirroring what the real FFI server does after
/// a successful POST /api/peers/relay/setup.
class _MockApiService extends ApiService {
  // Pass an explicit baseUrl so the ApiService constructor does not reach
  // into dotenv.env (which is unloaded in unit tests and would throw
  // NotInitializedError on the very first instantiation).
  _MockApiService(this._onSetupSuccess)
    : super(AuthService(), baseUrl: 'http://localhost:0');

  final void Function() _onSetupSuccess;

  int setupRelayCallCount = 0;
  String? lastRelayUrl;

  /// When false, [setupRelay] returns a 502-style response without flipping
  /// the FFI relay config. Lets tests assert the publish path skips when
  /// auto-setup fails.
  bool setupOk = true;

  @override
  Future<Response> setupRelay({required String relayUrl}) async {
    setupRelayCallCount++;
    lastRelayUrl = relayUrl;
    if (!setupOk) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/relay/setup'),
        statusCode: 502,
        data: const {'error': 'mock relay hub unreachable'},
      );
    }
    _onSetupSuccess();
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/relay/setup'),
      statusCode: 200,
      data: const {
        'mailbox_uuid': 'mbx-mock',
        'read_token': 'rt-mock',
        'write_token': 'wt-mock',
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a registered provider that has no local relay config. The provider
/// is pre-loaded from a synthetic [frb.FrbDirectoryConfig] so [_config]
/// is non-null and [ensureRelayPublished] does not bail on the early
/// `_config == null` guard.
Future<(HubDirectoryProvider, _MockFfiService, _MockApiService)>
_createProviderWithoutRelay({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'hub_directory_enabled': true,
    'libraryName': 'Test Library',
    'languageCode': 'en',
    'remoteReachableEnabled': true,
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  final api = _MockApiService(() {
    // Simulate the FFI server persisting fresh credentials after the
    // mocked successful POST /api/peers/relay/setup.
    ffi.relayConfig = const frb.FrbRelayConfig(
      relayUrl: 'https://hub.bibliogenius.org',
      mailboxUuid: 'mbx-mock',
      writeToken: 'wt-mock',
    );
  });

  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    apiService: api,
  );
  // Zero retry delays to keep the test under a second.
  provider.relayRetryDelay = Duration.zero;
  provider.relayCooldown = Duration.zero;

  // Hydrate the provider's _config so ensureRelayPublished does not
  // short-circuit on the early "_config == null" guard. The same path
  // exists in production: ensureRegistered runs before ensureRelayPublished.
  await provider.register(
    nodeId: 'test-node-id',
    displayName: 'Test Library',
    bookCount: 0,
    isListed: false,
    requiresApproval: false,
    acceptFrom: 'everyone',
    allowBorrowing: false,
  );

  return (provider, ffi, api);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // ApiService.hubUrl reads dotenv.env['HUB_URL']; loading an empty env
    // is enough so the static getter falls through to its non-release
    // default (http://localhost:8081) instead of throwing
    // NotInitializedError on first access.
    dotenv.testLoad();
  });

  group('HubDirectoryProvider auto-setup relay (point 5)', () {
    test(
      'ensureRelayPublished triggers setupRelay when local relay is missing',
      () async {
        final (provider, ffi, api) = await _createProviderWithoutRelay();
        // Sanity: the FFI mock starts with no relay config persisted.
        expect(await ffi.getRelayConfig(), isNull);

        await provider.ensureRelayPublished();

        // Auto-setup must have fired exactly once and reached the prod hub URL.
        expect(api.setupRelayCallCount, 1);
        expect(api.lastRelayUrl, ApiService.hubUrl);
      },
    );

    test(
      'ensureRelayPublished does not call setupRelay if local relay is present',
      () async {
        final (provider, ffi, api) = await _createProviderWithoutRelay();
        ffi.relayConfig = const frb.FrbRelayConfig(
          relayUrl: 'https://hub.bibliogenius.org',
          mailboxUuid: 'pre-existing-mbx',
          writeToken: 'pre-existing-wt',
        );

        await provider.ensureRelayPublished();

        expect(api.setupRelayCallCount, 0);
      },
    );

    test(
      'ensureRelayPublished skips setupRelay when remoteReachableEnabled is false',
      () async {
        final (provider, ffi, api) = await _createProviderWithoutRelay(
          prefs: const {'remoteReachableEnabled': false},
        );
        expect(await ffi.getRelayConfig(), isNull);

        await provider.ensureRelayPublished();

        // User has opted out of remote reachability: the provider must
        // honor the toggle and NOT auto-create a mailbox in their name.
        expect(api.setupRelayCallCount, 0);
      },
    );

    test(
      'failed setupRelay leaves the provider quiet (no publish loop)',
      () async {
        final (provider, ffi, api) = await _createProviderWithoutRelay();
        api.setupOk = false;

        await provider.ensureRelayPublished();

        expect(api.setupRelayCallCount, 1);
        // FFI relay config must remain null; no register-with-relay call
        // is fired since there are no creds to publish.
        expect(await ffi.getRelayConfig(), isNull);
      },
    );
  });
}
