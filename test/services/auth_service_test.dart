import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Set up FlutterSecureStorage mock
  FlutterSecureStorage.setMockInitialValues({});

  late AuthService authService;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    authService = AuthService();
  });

  tearDown(() {
    // Clear storage between tests to ensure isolation
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AuthService', () {
    test('saves and retrieves token', () async {
      await authService.saveToken('test_token');
      final token = await authService.getToken();
      expect(token, 'test_token');
    });

    test('saves and retrieves username', () async {
      await authService.saveUsername('test_user');
      final username = await authService.getUsername();
      expect(username, 'test_user');
    });

    test('isLoggedIn returns true when token exists', () async {
      await authService.saveToken('test_token');
      final loggedIn = await authService.isLoggedIn();
      expect(loggedIn, true);
    });

    test('isLoggedIn returns false when no token', () async {
      final loggedIn = await authService.isLoggedIn();
      expect(loggedIn, false);
    });

    test('logout clears token and username', () async {
      await authService.saveToken('test_token');
      await authService.saveUsername('test_user');

      await authService.logout();

      final token = await authService.getToken();
      final username = await authService.getUsername();
      final loggedIn = await authService.isLoggedIn();

      expect(token, null);
      expect(username, null);
      expect(loggedIn, false);
    });
  });

  // Pure reconciliation logic for the macOS Keychain <-> NSUserDefaults swing
  // (see e2ee_identity_storage_fragility.md). Platform-independent, so these
  // run everywhere.
  group('reconcileLibraryUuid', () {
    test('both present and equal -> use it, no writes', () {
      final r = reconcileLibraryUuid('U', 'U');
      expect(r.chosen, 'U');
      expect(r.needsSecureWrite, false);
      expect(r.needsPrefsWrite, false);
    });

    test('both present but different -> Keychain chosen, NO writes (non-destructive)', () {
      final r = reconcileLibraryUuid('KC', 'PREF');
      expect(r.chosen, 'KC');
      // Crucial: the prefs copy is NOT overwritten — it may be the value that
      // decrypts crypto_keys. Clobbering it could force an identity wipe.
      expect(r.needsSecureWrite, false);
      expect(r.needsPrefsWrite, false);
    });

    test('only Keychain present -> mirror to prefs', () {
      final r = reconcileLibraryUuid('KC', null);
      expect(r.chosen, 'KC');
      expect(r.needsSecureWrite, false);
      expect(r.needsPrefsWrite, true);
    });

    test('only prefs present -> mirror to Keychain', () {
      final r = reconcileLibraryUuid(null, 'PREF');
      expect(r.chosen, 'PREF');
      expect(r.needsSecureWrite, true);
      expect(r.needsPrefsWrite, false);
    });

    test('neither present -> chosen is null', () {
      final r = reconcileLibraryUuid(null, null);
      expect(r.chosen, null);
    });

    test('empty strings treated as absent', () {
      expect(reconcileLibraryUuid('', '').chosen, null);
      expect(reconcileLibraryUuid('', 'PREF').chosen, 'PREF');
      expect(reconcileLibraryUuid('KC', '').chosen, 'KC');
    });
  });

  // getOrCreateLibraryUuid wiring. The release-only macOS reconciliation path
  // cannot run under `flutter test` (always kDebugMode), so its logic is
  // covered by the reconcileLibraryUuid pure tests above. Here we guard the
  // non-regression of the bootstrap contract in the debug/test environment:
  // the UUID must persist (never silently regenerate) across calls.
  group('getOrCreateLibraryUuid (bootstrap contract)', () {
    setUp(() {
      AuthService.resetLibraryUuidCacheForTest();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('mints a non-empty UUID on first call', () async {
      final got = await AuthService().getOrCreateLibraryUuid();
      expect(got, isNotEmpty);
    });

    test('returns the same UUID across calls (no silent regeneration)',
        () async {
      final first = await AuthService().getOrCreateLibraryUuid();
      AuthService.resetLibraryUuidCacheForTest();
      final second = await AuthService().getOrCreateLibraryUuid();
      expect(second, first);
    });
  });
}
