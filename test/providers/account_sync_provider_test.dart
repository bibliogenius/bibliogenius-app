import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';

// ---------------------------------------------------------------------------
// Fake FfiService: returns canned JSON strings, mirroring what the Rust
// account-sync FFI produces, so the provider's parsing and error routing can
// be tested without the native backend.
// ---------------------------------------------------------------------------

class _FakeFfiService extends FfiService {
  _FakeFfiService() : super.forTest();

  String statusJson = '{"signed_in":false,"email":"","account_id":"","device_id":""}';
  String? signupResult;
  Object? signupError;
  String enrollResult =
      '{"signed_in":true,"email":"a@b.co","account_id":"acc","device_id":"d1"}';
  String enrollSealedResult =
      '{"signed_in":true,"email":"a@b.co","account_id":"acc","device_id":"d2"}';
  String devicesJson = '{"devices":[]}';
  String checkJson =
      '{"score":4,"length":16,"acceptable":true,"warning":"","suggestions":[]}';
  String syncNowJson = '{"synced":true,"applied":0,"pushed":3}';
  int syncNowCalls = 0;
  Object? syncNowError;

  @override
  Future<String> accountStatus() async => statusJson;

  @override
  Future<String> accountCheckPassphrase(String passphrase) async => checkJson;

  @override
  Future<String> accountSignup({
    required String email,
    required String passphrase,
    required String deviceName,
  }) async {
    if (signupError != null) throw signupError!;
    return signupResult!;
  }

  @override
  Future<String> accountEnrollPassphrase({
    required String email,
    required String passphrase,
    required String deviceName,
  }) async => enrollResult;

  @override
  Future<String> accountEnrollFromSealed(String sealedQrPayload) async =>
      enrollSealedResult;

  @override
  Future<String> accountRefreshDevices() async => devicesJson;

  String removeDevicesJson = '{"devices":[]}';
  String? removedDeviceId;
  Object? removeError;

  @override
  Future<String> accountRemoveDevice(String deviceId) async {
    removedDeviceId = deviceId;
    if (removeError != null) throw removeError!;
    return removeDevicesJson;
  }

  @override
  Future<String> accountSyncNow() async {
    syncNowCalls++;
    if (syncNowError != null) throw syncNowError!;
    return syncNowJson;
  }

  @override
  Future<String> accountLogout() async => 'Signed out';
}

void main() {
  late _FakeFfiService ffi;
  late AccountSyncProvider provider;

  setUp(() {
    ffi = _FakeFfiService();
    provider = AccountSyncProvider(ffi: ffi);
  });

  test('refreshStatus parses the signed-in metadata', () async {
    ffi.statusJson =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-1","device_id":"dev-1"}';
    await provider.refreshStatus();

    expect(provider.signedIn, isTrue);
    expect(provider.status.email, 'me@lib.org');
    expect(provider.status.accountId, 'acc-1');
    expect(provider.status.deviceId, 'dev-1');
  });

  test('signup returns the one-time recovery phrase and sets status', () async {
    ffi.signupResult =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-9",'
        '"device_id":"dev-9","recovery_phrase":"word1 word2 word3"}';

    final result = await provider.signup(
      email: 'me@lib.org',
      passphrase: 'a-strong-passphrase',
      deviceName: 'Mac',
    );

    expect(result.recoveryPhrase, 'word1 word2 word3');
    expect(result.status.accountId, 'acc-9');
    expect(provider.signedIn, isTrue);
  });

  test('signup surfaces the restart_required flag', () async {
    ffi.signupResult =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-9",'
        '"device_id":"dev-9","recovery_phrase":"w1 w2","restart_required":true}';

    final result = await provider.signup(
      email: 'me@lib.org',
      passphrase: 'a-strong-passphrase',
      deviceName: 'Mac',
    );

    expect(result.restartRequired, isTrue);
  });

  test('joinWithPassphrase returns restart_required from the response',
      () async {
    ffi.enrollResult =
        '{"signed_in":true,"email":"a@b.co","account_id":"acc",'
        '"device_id":"d1","restart_required":true}';

    final restartRequired = await provider.joinWithPassphrase(
      email: 'a@b.co',
      passphrase: 'a-strong-passphrase',
      deviceName: 'Mac',
    );

    expect(restartRequired, isTrue);
    expect(provider.signedIn, isTrue);
  });

  test('joinWithPassphrase defaults restart_required to false when absent',
      () async {
    // enrollResult has no restart_required key (the default fixture).
    final restartRequired = await provider.joinWithPassphrase(
      email: 'a@b.co',
      passphrase: 'a-strong-passphrase',
      deviceName: 'Mac',
    );

    expect(restartRequired, isFalse);
  });

  test('enrollFromSealed returns restart_required from the response', () async {
    ffi.enrollSealedResult =
        '{"signed_in":true,"email":"a@b.co","account_id":"acc",'
        '"device_id":"d2","restart_required":true}';

    final restartRequired = await provider.enrollFromSealed('bg-sealed.payload');

    expect(restartRequired, isTrue);
    expect(provider.signedIn, isTrue);
  });

  test('signup routes E_ACCOUNT_EXISTS to a recoverable exception', () async {
    ffi.signupError = Exception('E_ACCOUNT_EXISTS: already registered');

    expect(
      () => provider.signup(
        email: 'taken@lib.org',
        passphrase: 'a-strong-passphrase',
        deviceName: 'Mac',
      ),
      throwsA(
        isA<AccountSignupException>()
            .having((e) => e.accountExists, 'accountExists', isTrue)
            .having((e) => e.weakPassphrase, 'weakPassphrase', isFalse),
      ),
    );
  });

  test('signup routes E_WEAK_PASSPHRASE to the weak-passphrase backstop',
      () async {
    ffi.signupError = Exception('E_WEAK_PASSPHRASE: too weak');

    expect(
      () => provider.signup(
        email: 'me@lib.org',
        passphrase: 'weak',
        deviceName: 'Mac',
      ),
      throwsA(
        isA<AccountSignupException>()
            .having((e) => e.weakPassphrase, 'weakPassphrase', isTrue)
            .having((e) => e.accountExists, 'accountExists', isFalse),
      ),
    );
  });

  test('refreshDevices parses the device list and the self flag', () async {
    ffi.devicesJson =
        '{"devices":[{"device_id":"d1","name":"Mac","is_self":true},'
        '{"device_id":"d2","name":"iPhone","is_self":false}]}';
    await provider.refreshDevices();

    expect(provider.devices.length, 2);
    expect(provider.devices.first.name, 'Mac');
    expect(provider.devices.first.isSelf, isTrue);
    expect(provider.devices[1].isSelf, isFalse);
  });

  test('removeDevice forwards the id and updates the list from the response',
      () async {
    ffi.devicesJson =
        '{"devices":[{"device_id":"d1","name":"Mac","is_self":true},'
        '{"device_id":"d2","name":"iPhone","is_self":false}]}';
    await provider.refreshDevices();
    expect(provider.devices.length, 2);

    // The FFI returns the shrunk list; the provider adopts it.
    ffi.removeDevicesJson =
        '{"devices":[{"device_id":"d1","name":"Mac","is_self":true}]}';
    await provider.removeDevice('d2');

    expect(ffi.removedDeviceId, 'd2');
    expect(provider.devices, hasLength(1));
    expect(provider.devices.single.deviceId, 'd1');
  });

  test('removeDevice rethrows and leaves the list unchanged on failure',
      () async {
    ffi.devicesJson =
        '{"devices":[{"device_id":"d1","name":"Mac","is_self":true},'
        '{"device_id":"d2","name":"iPhone","is_self":false}]}';
    await provider.refreshDevices();

    ffi.removeError = Exception('cannot remove the current device');
    await expectLater(provider.removeDevice('d1'), throwsA(isA<Exception>()));
    expect(provider.devices, hasLength(2));
  });

  test('checkPassphrase returns empty score for a blank input without FFI',
      () async {
    final s = await provider.checkPassphrase('');
    expect(s.score, 0);
    expect(s.acceptable, isFalse);
  });

  test('checkPassphrase parses the score and acceptability', () async {
    ffi.checkJson =
        '{"score":4,"length":18,"acceptable":true,"warning":"","suggestions":[]}';
    final s = await provider.checkPassphrase('a-strong-passphrase');
    expect(s.score, 4);
    expect(s.acceptable, isTrue);
  });

  test('syncNow returns the backend result and refreshes the device list',
      () async {
    ffi.syncNowJson = '{"synced":true,"applied":1,"pushed":2}';
    ffi.devicesJson =
        '{"devices":[{"device_id":"d1","name":"Mac","is_self":true}]}';

    final raw = await provider.syncNow();

    expect(raw, contains('"pushed":2'));
    // syncNow refreshes the registry-derived device list as part of the cycle.
    expect(provider.devices, hasLength(1));
    expect(provider.devices.first.name, 'Mac');
  });

  test('logout clears the session state', () async {
    ffi.statusJson =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-1","device_id":"dev-1"}';
    await provider.refreshStatus();
    expect(provider.signedIn, isTrue);

    await provider.logout();
    expect(provider.signedIn, isFalse);
    expect(provider.devices, isEmpty);
  });

  test('autoSyncTick no-ops when signed out', () async {
    // Default status is signed-out.
    final ran = await provider.autoSyncTick();
    expect(ran, isFalse);
    expect(ffi.syncNowCalls, 0, reason: 'no sync attempted when signed out');
  });

  test('autoSyncTick runs a cycle when signed in, without touching busy/error',
      () async {
    ffi.statusJson =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-1","device_id":"dev-1"}';
    await provider.refreshStatus();

    final ran = await provider.autoSyncTick();
    expect(ran, isTrue);
    expect(ffi.syncNowCalls, 1);
    // A background tick must stay invisible: no spinner, no surfaced error.
    expect(provider.busy, isFalse);
    expect(provider.error, isNull);
  });

  test('autoSyncTick swallows a network failure silently', () async {
    ffi.statusJson =
        '{"signed_in":true,"email":"me@lib.org","account_id":"acc-1","device_id":"dev-1"}';
    await provider.refreshStatus();
    ffi.syncNowError = Exception('hub unreachable');

    final ran = await provider.autoSyncTick();
    expect(ran, isFalse, reason: 'a failed cycle reports not-ran for backoff');
    expect(provider.error, isNull, reason: 'failure must not surface in the UI');
    expect(provider.busy, isFalse);
  });
}
