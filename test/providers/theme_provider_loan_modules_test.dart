import 'dart:io';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUpAll(() {
    tempRoot = Directory.systemTemp.createTempSync('loan_modules_prefs_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempRoot.path);
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ThemeProvider canLendBooks', () {
    test('defaults to true on fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();
      expect(
        provider.canLendBooks,
        isTrue,
        reason:
            'Lending is the default historical behavior; users opt out '
            'explicitly via the new module toggle.',
      );
    });

    test('setCanLendBooks persists and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setCanLendBooks(false);
      expect(provider.canLendBooks, isFalse);
      expect(notifications, greaterThanOrEqualTo(1));

      // Persistence round-trip across a fresh provider instance.
      final fresh = ThemeProvider();
      await fresh.loadSettings();
      expect(fresh.canLendBooks, isFalse);
    });

    test('canLendBooks is independent of canBorrowBooks', () async {
      // The two modules must be orthogonal: the user must be able to disable
      // one without affecting the other (a librarian lends but does not
      // borrow; a pure reader may want to borrow without lending).
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      await provider.setCanLendBooks(false);
      expect(provider.canLendBooks, isFalse);
      expect(
        provider.canBorrowBooks,
        isTrue,
        reason: 'Toggling lending must not flip the borrowing flag.',
      );

      await provider.setCanBorrowBooks(false);
      expect(provider.canBorrowBooks, isFalse);
      expect(provider.canLendBooks, isFalse);

      await provider.setCanLendBooks(true);
      expect(provider.canLendBooks, isTrue);
      expect(
        provider.canBorrowBooks,
        isFalse,
        reason: 'Toggling lending back on must not re-enable borrowing.',
      );
    });

    test('loadSettings preserves a stored false value', () async {
      // The default fallback is true; without explicit persistence handling,
      // a stored false would be silently overwritten on restart.
      SharedPreferences.setMockInitialValues({'canLendBooks': false});
      final provider = ThemeProvider();
      await provider.loadSettings();
      expect(provider.canLendBooks, isFalse);
    });
  });
}
