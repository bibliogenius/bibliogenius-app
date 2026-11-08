import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/utils/backup_actions.dart';

// A reset deletes rows from the account-sync replicated tables, and those
// deletes reach every device of the account. The full reset signs out first so
// it stays local, and a failed reset must not announce success; the partial
// resets warn when other devices would follow.

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

  group('resetReachesOtherDevices', () {
    test('is false without an account', () async {
      expect(await BackupActions.resetReachesOtherDevices(provider), isFalse);
    });

    test('is false when this device is the only one', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesJson =
          '{"devices":[{"device_id":"d1","name":"Mac","is_self":true}]}';
      expect(await BackupActions.resetReachesOtherDevices(provider), isFalse);
    });

    test('is true when the account is on another device', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesJson =
          '{"devices":[{"device_id":"d1","name":"Mac","is_self":true},'
          '{"device_id":"d2","name":"iPhone","is_self":false}]}';
      expect(await BackupActions.resetReachesOtherDevices(provider), isTrue);
    });

    test('is true when the device list cannot be fetched', () async {
      ffi.statusJson = _signedIn;
      ffi.devicesError = Exception('offline');
      expect(await BackupActions.resetReachesOtherDevices(provider), isTrue);
    });

    test('is true when the account status cannot be read', () async {
      // The provider keeps its last known status on a failed read, here the
      // initial signed-out one: the reset must not trust it and stay silent.
      ffi.statusError = Exception('db locked');
      expect(await BackupActions.resetReachesOtherDevices(provider), isTrue);
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

  group('ensureResetSucceeded', () {
    Response<dynamic> response(int status, Object? data) => Response(
      requestOptions: RequestOptions(path: '/api/reset'),
      statusCode: status,
      data: data,
    );

    test('accepts a successful reset', () {
      BackupActions.ensureResetSucceeded(
        response(200, {'success': true, 'message': 'ok'}),
      );
    });

    test('throws the FFI error carried by a 500 response', () {
      expect(
        () => BackupActions.ensureResetSucceeded(
          response(500, {'success': false, 'message': 'Failed to delete book'}),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to delete book'),
          ),
        ),
      );
    });

    test('throws on a failure without a message', () {
      expect(
        () => BackupActions.ensureResetSucceeded(response(500, null)),
        throwsException,
      );
    });
  });
}
