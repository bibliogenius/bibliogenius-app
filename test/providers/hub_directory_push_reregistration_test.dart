import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ADR-073: the hub removes a profile nobody may read after 30 days of
// silence. An installation with a relay finds out through its profile
// update at startup. One without a relay sends no profile update: its first
// contact is the catalog push, refused because its token names no profile
// any more. It must register again there, or it would stay refused forever.

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => null;

  @override
  Future<String?> getAppVersion() async => '1.4.2';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// What the hub answers to a push: refused until the library registers
  /// again, as after a purge. Null means every push is accepted.
  String? pushErrorUntilRegistered;

  bool refusedEvenAfterRegistering = false;

  int registerCalls = 0;
  int pushAttempts = 0;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      frb.FrbDirectoryConfig(
        nodeId: 'node-1',
        isListed: !privateLibrary,
        requiresApproval: privateLibrary,
        acceptFrom: 'everyone',
        allowBorrowing: false,
      );

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 7;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => null;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCalls++;
    return frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: !privateLibrary,
      requiresApproval: privateLibrary,
      acceptFrom: params.acceptFrom,
      allowBorrowing: false,
    );
  }

  /// An approval-required, unlisted library: its catalog goes encrypted
  /// once the (empty) list of followers can be read.
  bool privateLibrary = false;
  int encryptedPushes = 0;
  int clearPushes = 0;

  /// A failure of the followers read that is not a refused token.
  String? followersError;

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async {
    final error = followersError;
    if (error != null) throw StateError(error);
    // The dead token cannot read the followers either.
    if (registerCalls == 0) throw StateError('Hub error 401: unauthorized');
    return const [];
  }

  @override
  Future<int> hubDirectorySyncCatalogEncrypted() async {
    encryptedPushes++;
    return _push();
  }

  @override
  Future<int> hubDirectorySyncCatalog() async {
    clearPushes++;
    return _push();
  }

  Future<int> _push() async {
    pushAttempts++;
    final error = pushErrorUntilRegistered;
    if (error != null && (registerCalls == 0 || refusedEvenAfterRegistering)) {
      lastCatalogSyncError = error;
      return -1;
    }
    lastCatalogSyncError = null;
    return 7;
  }
}

Future<(HubDirectoryProvider, _MockFfiService)> _registeredWithoutRelay({
  bool privateLibrary = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'libraryName': 'Test Library',
    'languageCode': 'en',
    'remoteReachableEnabled': false,
  });
  AuthService.storage = MockSecureStorage();
  dotenv.testLoad();
  final ffi = _MockFfiService()..privateLibrary = privateLibrary;
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await provider.loadConfig();
  return (provider, ffi);
}

void main() {
  test('a push refused for an unknown token registers again, then pushes', () async {
    final (provider, ffi) = await _registeredWithoutRelay();
    ffi.pushErrorUntilRegistered =
        'Hub error 401: {"error":"Invalid write_token."}';

    final pushed = await provider.syncCatalog();

    expect(ffi.registerCalls, 1);
    expect(ffi.pushAttempts, 2);
    expect(pushed, 7);
  });

  test('a private catalog whose followers a dead token cannot read registers '
      'again, then goes out encrypted, never in clear', () async {
    // With the dead token the followers cannot be read, so nothing can be
    // decided and nothing is pushed. The refusal itself says the profile
    // is gone: once registered again the followers are read and the
    // catalog is encrypted.
    final (provider, ffi) = await _registeredWithoutRelay(privateLibrary: true);

    final pushed = await provider.syncCatalog();

    expect(ffi.registerCalls, 1);
    expect(ffi.encryptedPushes, 1);
    expect(ffi.clearPushes, 0);
    expect(pushed, 7);
  });

  test('followers unreadable for another reason: nothing registers and '
      'nothing is pushed', () async {
    final (provider, ffi) = await _registeredWithoutRelay(privateLibrary: true);
    ffi.followersError = 'hub unreachable';

    expect(await provider.syncCatalog(), -1);

    expect(ffi.registerCalls, 0);
    expect(ffi.pushAttempts, 0);
  });

  test('it registers again once per run, not at every refused push', () async {
    final (provider, ffi) = await _registeredWithoutRelay();
    // A refusal that registering again does not cure.
    ffi
      ..pushErrorUntilRegistered = 'Hub error 401: {"error":"Invalid write_token."}'
      ..refusedEvenAfterRegistering = true;

    expect(await provider.syncCatalog(), -1);
    expect(await provider.syncCatalog(), -1);

    expect(ffi.registerCalls, 1);
  });

  test('any other push failure registers nothing', () async {
    final (provider, ffi) = await _registeredWithoutRelay();
    ffi.pushErrorUntilRegistered = 'Hub error 413: catalog too large';

    expect(await provider.syncCatalog(), -1);

    expect(ffi.registerCalls, 0);
    expect(ffi.pushAttempts, 1);
  });
}
