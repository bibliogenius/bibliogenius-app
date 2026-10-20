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

/// A hub that still holds a published profile for this library while the
/// local registration row is gone (hub switch, 401 recovery): what it
/// returns after an upsert is what it holds, flags included.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  frb.FrbDirectoryConfig? config;
  final List<frb.FrbRegisterParams> registerParamsLog = [];

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => config;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 3;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerParamsLog.add(params);
    config = frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      // The hub's stored settings, which the Rust side copies locally.
      isListed: params.isListed ?? true,
      requiresApproval: params.requiresApproval ?? false,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing ?? true,
    );
    return config;
  }

  @override
  Future<String?> hubDirectoryExportWriteToken() async => 'token';

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageInterface previousStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'hub_directory_enabled': true,
      'libraryName': 'My shelves',
    });
    previousStorage = AuthService.storage;
    AuthService.storage = MockSecureStorage();
    AuthService.hubUrlResolver = () async => 'https://hub-a.example.org';
  });

  tearDown(() {
    AuthService.storage = previousStorage;
    AuthService.resetHubUrlResolverForTest();
  });

  test('a silent registration sends no visibility flag and mirrors the hub',
      () async {
    final ffi = _MockFfiService();
    final provider = HubDirectoryProvider(
      ffi: ffi,
      apiService: _MockApiService(),
      deviceService: _MockDeviceService(),
    );
    await provider.loadConfig();
    expect(provider.isRegistered, isFalse);

    final ok = await provider.ensureRegistered();

    expect(ok, isTrue);
    final params = ffi.registerParamsLog.single;
    // Before this change the silent registration sent false for all three,
    // which unlisted a published library coming back from a hub switch.
    expect(params.isListed, isNull);
    expect(params.requiresApproval, isNull);
    expect(params.allowBorrowing, isNull);
    expect(params.acceptFrom, 'everyone');
    // The local config now says what the hub holds.
    expect(provider.config?.isListed, isTrue);
    expect(provider.config?.requiresApproval, isFalse);
    expect(provider.config?.allowBorrowing, isTrue);
  });

  test('publishing from the discover banner still sets the flags', () async {
    final ffi = _MockFfiService();
    final provider = HubDirectoryProvider(
      ffi: ffi,
      apiService: _MockApiService(),
      deviceService: _MockDeviceService(),
    );
    await provider.loadConfig();

    final ok = await provider.enableAndPublish(displayName: 'My shelves');

    expect(ok, isTrue);
    final params = ffi.registerParamsLog.single;
    expect(params.isListed, isTrue);
    expect(params.requiresApproval, isTrue);
    expect(params.allowBorrowing, isFalse);
  });
}
