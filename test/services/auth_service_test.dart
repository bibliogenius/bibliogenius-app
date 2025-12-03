import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  // Set up FlutterSecureStorage mock
  FlutterSecureStorage.setMockInitialValues({});

  late AuthService authService;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
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
}
