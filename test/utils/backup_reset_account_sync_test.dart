import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/utils/backup_actions.dart';

// A reset deletes rows from the account-sync replicated tables, and those
// deletes reach every device of the account. The full reset signs out first so
// it stays local; the partial resets warn when other devices would follow.

const _signedOut =
    '{"signed_in":false,"email":"","account_id":"","device_id":""}';
const _signedIn =
    '{"signed_in":true,"email":"a@b.co","account_id":"acc","device_id":"d1"}';

class _FakeFfiService extends FfiService {
  _FakeFfiService() : super.forTest();

  String statusJson = _signedOut;
  String devicesJson = '{"devices":[]}';
  Object? statusError;
  Object? devicesError;
  Object? logoutError;
  int logoutCalls = 0;

  @override
  Future<String> accountStatus() async {
    if (statusError != null) throw statusError!;
    return statusJson;
  }

  @override
  Future<String> accountRefreshDevices() async {
    if (devicesError != null) throw devicesError!;
    return devicesJson;
  }

  @override
  Future<String> accountLogout() async {
    logoutCalls++;
    if (logoutError != null) throw logoutError!;
    return 'Signed out';
  }
}

void main() {
  late _FakeFfiService ffi;
  late AccountSyncProvider provider;

  setUp(() {
    ffi = _FakeFfiService();
    provider = AccountSyncProvider(ffi: ffi);
  });

  group('otherDevicesWarning', () {
    test('is empty without an account', () async {
      expect(await BackupActions.otherDevicesWarning(provider), isEmpty);
    });

    test('is empty when this device is the only one', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesJson =
          '{"devices":[{"device_id":"d1","name":"Mac","is_self":true}]}';
      expect(await BackupActions.otherDevicesWarning(provider), isEmpty);
    });

    test('warns when the account is on another device', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesJson =
          '{"devices":[{"device_id":"d1","name":"Mac","is_self":true},'
          '{"device_id":"d2","name":"iPhone","is_self":false}]}';
      expect(
        await BackupActions.otherDevicesWarning(provider),
        contains('tous les appareils'),
      );
    });

    test('warns when the device list cannot be fetched', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesError = Exception('offline');
      expect(
        await BackupActions.otherDevicesWarning(provider),
        contains('tous les appareils'),
      );
    });
  });

  group('signOutBeforeFullReset', () {
    test('does not sign out a device without an account', () async {
      await BackupActions.signOutBeforeFullReset(provider);
      expect(ffi.logoutCalls, 0);
    });

    test('signs a signed-in device out', () async {
      ffi.statusJson = _signedIn;
      await BackupActions.signOutBeforeFullReset(provider);
      expect(ffi.logoutCalls, 1);
      expect(provider.signedIn, isFalse);
    });

    test('throws when sign-out fails, so the reset aborts', () async {
      ffi.statusJson = _signedIn;
      ffi.logoutError = Exception('db locked');
      await expectLater(
        BackupActions.signOutBeforeFullReset(provider),
        throwsException,
      );
    });

    test('throws when the account status cannot be read', () async {
      ffi.statusError = Exception('db locked');
      await expectLater(
        BackupActions.signOutBeforeFullReset(provider),
        throwsException,
      );
      expect(ffi.logoutCalls, 0);
    });
  });
}
