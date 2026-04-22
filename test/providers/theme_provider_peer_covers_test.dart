import 'dart:io';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/peer_book_cover_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake platform implementation that returns a throwaway temp directory.
/// The ThemeProvider cap setter constructs a [CacheManager], which eagerly
/// opens its JSON metadata store via path_provider -- without this stub,
/// every test that hits the setter throws MissingPluginException.
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
  // ThemeProvider.loadSettings touches WidgetsBinding (via ImageCache), so
  // we need the test binding up before any test body runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared for the whole file so a CacheManager instance from an earlier
  // test that keeps doing async work in the background (flutter_cache_manager
  // opens its store lazily) cannot race with a per-test tearDown cleanup.
  late Directory tempRoot;

  setUpAll(() {
    tempRoot =
        Directory.systemTemp.createTempSync('peer_cover_prefs_test_');
    PathProviderPlatform.instance =
        _FakePathProviderPlatform(tempRoot.path);
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup; the OS will reclaim systemTemp anyway.
    }
  });

  setUp(() {
    // ThemeProvider.loadSettings falls back to AuthService.getUsername()
    // when the 'username' pref is absent -- which hits flutter_secure_storage.
    // That plugin is unavailable on headless Linux CI unless explicitly
    // mocked, so the read throws MissingPluginException and the whole
    // loadSettings call fails. Stubbing the mock values at the storage
    // layer is the canonical pattern used by auth_service_test.dart.
    FlutterSecureStorage.setMockInitialValues({});
    // Defensive: earlier tests in the same process might have left the
    // manager in a non-default state. Reset before each test so
    // `capMb` and `_instance` are predictable.
    PeerBookCoverCacheManager.resetForTest();
  });

  group('ThemeProvider peer cover prefs defaults', () {
    test('peerCoverDisplayEnabled defaults to true on fresh install',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();
      expect(provider.peerCoverDisplayEnabled, isTrue,
          reason:
              'Showing peer covers by default preserves the discovery UX; '
              'users opt into the data-saver mode explicitly.');
    });

    test('peerCoverCacheCapMb defaults to 100 MB on fresh install',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();
      expect(provider.peerCoverCacheCapMb, equals(100));
    });

    test('peerCoverCacheCapChoicesMb exposes the Settings selector values',
        () {
      expect(
        ThemeProvider.peerCoverCacheCapChoicesMb,
        equals(const [50, 100, 200, 500]),
        reason:
            'The Settings dropdown is the single source of truth for legal '
            'cap values. Changing this list requires updating the UI AND '
            'the clamp logic in loadSettings.',
      );
    });
  });

  group('ThemeProvider peer cover prefs persistence', () {
    test('setPeerCoverDisplayEnabled persists and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setPeerCoverDisplayEnabled(false);
      expect(provider.peerCoverDisplayEnabled, isFalse);
      expect(notifications, greaterThanOrEqualTo(1));

      // Persistence round-trip
      final fresh = ThemeProvider();
      await fresh.loadSettings();
      expect(fresh.peerCoverDisplayEnabled, isFalse);
    });

    test('setPeerCoverCacheCapMb persists the new cap', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      await provider.setPeerCoverCacheCapMb(200);
      expect(provider.peerCoverCacheCapMb, equals(200));

      final fresh = ThemeProvider();
      await fresh.loadSettings();
      expect(fresh.peerCoverCacheCapMb, equals(200));
    });

    test('setPeerCoverCacheCapMb rejects out-of-range values', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      await provider.setPeerCoverCacheCapMb(123); // not in [50,100,200,500]
      expect(
        provider.peerCoverCacheCapMb,
        equals(100),
        reason:
            'Silently rejecting invalid values keeps the Settings UI the '
            'single source of truth for legal caps. A value from a stale '
            'build or a manual prefs edit must not leak through.',
      );
    });

    test('setPeerCoverCacheCapMb is idempotent for unchanged value',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setPeerCoverCacheCapMb(100); // already 100
      expect(notifications, equals(0),
          reason:
              'No-op setter must not notify -- listeners should only rebuild '
              'when the cap actually changes.');
    });
  });

  group('ThemeProvider peer cover prefs clamping', () {
    test('loadSettings clamps an invalid stored cap to the default',
        () async {
      // Simulates a prefs entry left over from a future build or a manual
      // edit. The clamp prevents the Settings selector from rendering
      // with "no value selected".
      SharedPreferences.setMockInitialValues({
        'peerCoverCacheCapMb': 999,
      });
      final provider = ThemeProvider();
      await provider.loadSettings();

      expect(provider.peerCoverCacheCapMb, equals(100));
    });

    test('loadSettings preserves a valid stored cap', () async {
      SharedPreferences.setMockInitialValues({
        'peerCoverCacheCapMb': 500,
      });
      final provider = ThemeProvider();
      await provider.loadSettings();

      expect(provider.peerCoverCacheCapMb, equals(500));
    });
  });

  group('PeerBookCoverCacheManager follows the cap on setter', () {
    test('setPeerCoverCacheCapMb propagates the cap to the cache manager',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.loadSettings();

      await provider.setPeerCoverCacheCapMb(200);
      expect(PeerBookCoverCacheManager.capMb, equals(200),
          reason:
              'The setter must call configure() so the manager applies the '
              'new cap immediately -- otherwise peer views would keep the '
              'old eviction threshold until the next app launch.');
    });
  });
}
