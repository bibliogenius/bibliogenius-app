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
// Fixtures
// ---------------------------------------------------------------------------

const _hubA = 'https://hub-a.example.org';
const _hubB = 'https://hub-b.example.org';

/// A hub seen through the FFI after the local database lost its
/// registration (reinstall, or a hub switch that purged the row): the
/// provider must restore the write token from the Keychain, and only the
/// one issued by the hub it talks to.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  frb.FrbDirectoryConfig? config;

  /// What the hub would issue on registration, backed up to the Keychain.
  String issuedToken = 'unset';

  /// Every token imported from the Keychain, in order.
  final List<String> importedTokens = [];

  /// Every registration, in order.
  final List<frb.FrbRegisterParams> registerParamsLog = [];

  /// What the hub holds for the flags a registration leaves out.
  bool hubIsListed = false;
  bool hubRequiresApproval = true;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => config;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 1;

  @override
  Future<String?> getLocalX25519PublicKey() async => null;

  @override
  Future<bool> hubDirectoryImportWriteToken({
    required String nodeId,
    required String writeToken,
  }) async {
    importedTokens.add(writeToken);
    config = frb.FrbDirectoryConfig(
      nodeId: nodeId,
      isListed: false,
      requiresApproval: true,
      acceptFrom: 'everyone',
      allowBorrowing: false,
    );
    return true;
  }

  /// When set, the next registration carrying a token is refused as the
  /// hub refuses a token it did not issue; an unauthenticated one passes.
  bool rejectStaleToken = false;
  int purges = 0;

  @override
  Future<bool> hubDirectoryPurgeConfig() async {
    purges++;
    config = null;
    return true;
  }

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    if (rejectStaleToken && config != null) {
      // The Rust side maps the hub's 401 to this message.
      throw Exception('Hub error 401: Valid write_token required');
    }
    registerParamsLog.add(params);
    config = frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed ?? hubIsListed,
      requiresApproval: params.requiresApproval ?? hubRequiresApproval,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing ?? false,
    );
    return config;
  }

  @override
  Future<String?> hubDirectoryExportWriteToken() async => issuedToken;

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => null;
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
}

HubDirectoryProvider _provider(_MockFfiService ffi) => HubDirectoryProvider(
  ffi: ffi,
  apiService: _MockApiService(),
  deviceService: _MockDeviceService(),
);

Future<void> _registerOn(String hub, _MockFfiService ffi, String token) async {
  AuthService.hubUrlResolver = () async => hub;
  ffi.issuedToken = token;
  final ok = await _provider(ffi).register(
    nodeId: 'node-1',
    displayName: 'Library',
    bookCount: 1,
    isListed: false,
    requiresApproval: true,
    acceptFrom: 'everyone',
    allowBorrowing: false,
  );
  expect(ok, isTrue);
}

/// A fresh launch on [hub] whose local database lost its registration.
Future<void> _relaunchOn(String hub, _MockFfiService ffi) async {
  AuthService.hubUrlResolver = () async => hub;
  ffi.config = null;
  await _provider(ffi).loadConfig();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageInterface previousStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({'hub_directory_enabled': true});
    previousStorage = AuthService.storage;
    AuthService.storage = MockSecureStorage();
  });

  tearDown(() {
    AuthService.storage = previousStorage;
    AuthService.resetHubUrlResolverForTest();
  });

  group('Keychain recovery of the hub write token', () {
    test('a build switched between two hubs restores each hub its own token',
        () async {
      final ffi = _MockFfiService();
      await _registerOn(_hubA, ffi, 'token-a');
      await _registerOn(_hubB, ffi, 'token-b');

      await _relaunchOn(_hubA, ffi);

      // Before per-hub slots, the Keychain held the last token written,
      // token-b, which hub A would refuse with a 401 and a re-registration.
      expect(ffi.importedTokens, ['token-a']);
      expect(await ffi.hubDirectoryGetConfig(), isNotNull);
    });

    test('a hub never registered on restores nothing', () async {
      final ffi = _MockFfiService();
      await _registerOn(_hubA, ffi, 'token-a');

      await _relaunchOn(_hubB, ffi);

      expect(ffi.importedTokens, isEmpty);
      expect(await ffi.hubDirectoryGetConfig(), isNull);
    });

    test('a stale token on one hub is dropped for that hub only', () async {
      // Hub A issued token-a; the build then registered on hub B. Back on
      // hub A with a token hub A no longer accepts: the 401 recovery must
      // forget hub A's slot only, re-register fresh and keep hub B's token.
      final ffi = _MockFfiService();
      await _registerOn(_hubA, ffi, 'token-a');
      await _registerOn(_hubB, ffi, 'token-b');

      await _relaunchOn(_hubA, ffi);
      expect(ffi.importedTokens, ['token-a']);
      ffi.rejectStaleToken = true;
      ffi.issuedToken = 'token-a2';
      final ok = await _provider(ffi).register(
        nodeId: 'node-1',
        displayName: 'Library',
        bookCount: 1,
        acceptFrom: 'everyone',
      );

      expect(ok, isTrue);
      expect(ffi.purges, 1);
      final auth = AuthService();
      expect(await auth.getHubWriteToken(), 'token-a2');
      AuthService.hubUrlResolver = () async => _hubB;
      expect(await auth.getHubWriteToken(), 'token-b');
    });

    test('a registration restored from the Keychain mirrors the hub at startup',
        () async {
      // The import writes a default row (unlisted, approval required); the
      // hub still holds a published profile. One flag-less registration at
      // startup brings the local copy in line before any catalog push.
      final ffi = _MockFfiService();
      await _registerOn(_hubA, ffi, 'token-a');
      ffi.config = null;
      ffi.hubIsListed = true;
      ffi.hubRequiresApproval = false;
      final provider = _provider(ffi);

      await provider.initAndSyncCatalog();

      expect(ffi.importedTokens, ['token-a']);
      final params = ffi.registerParamsLog.last;
      expect(params.isListed, isNull);
      expect(params.requiresApproval, isNull);
      expect(params.allowBorrowing, isNull);
      expect(provider.config?.isListed, isTrue);
      expect(provider.config?.requiresApproval, isFalse);
    });

    test('an installation with the unscoped slot still restores its token',
        () async {
      await AuthService.storage.write(key: 'hub_write_token', value: 'legacy');
      final ffi = _MockFfiService();

      await _relaunchOn(_hubA, ffi);

      expect(ffi.importedTokens, ['legacy']);
    });
  });
}
