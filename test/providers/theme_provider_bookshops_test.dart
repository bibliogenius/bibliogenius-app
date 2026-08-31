import 'dart:io';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/utils/library_portals.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    tempRoot = Directory.systemTemp.createTempSync('bookshops_prefs_test_');
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
    ThemeProvider.seedFavoritesOverride = () async => true;
    // The preset setters reach ApiService, which reads dotenv (unloaded in
    // tests unless primed).
    dotenv.testLoad();
  });

  tearDown(() {
    ThemeProvider.seedFavoritesOverride = null;
  });

  Future<ThemeProvider> load() async {
    final provider = ThemeProvider();
    await provider.loadSettings();
    return provider;
  }

  group('bookshop-linking prefs', () {
    test('fresh install defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await load();
      expect(provider.showBookshopFinder, isTrue);
      expect(provider.showLibraryLinks, isTrue);
      expect(provider.myBookshopIds, isEmpty);
      expect(provider.myCustomBookshops, isEmpty);
      expect(provider.myLibraryPortals, isEmpty);
    });

    test('my bookshops round-trip through a fresh provider, in order',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await load();
      await provider.addMyBookshop('leslibraires-fr');
      await provider.addMyBookshop('placedeslibraires');
      await provider.addMyBookshop('leslibraires-fr'); // duplicate ignored

      final reloaded = await load();
      expect(reloaded.myBookshopIds, [
        'leslibraires-fr',
        'placedeslibraires',
      ]);

      await reloaded.removeMyBookshop('leslibraires-fr');
      expect((await load()).myBookshopIds, ['placedeslibraires']);
    });

    test('library portals round-trip; same template not added twice',
        () async {
      SharedPreferences.setMockInitialValues({});
      const portal = LocalLibraryPortal(
        name: 'Mediatheque test',
        urlTemplate: 'https://opac.example.fr/?q={ean13}',
      );
      final provider = await load();
      await provider.addMyLibraryPortal(portal);
      await provider.addMyLibraryPortal(
        const LocalLibraryPortal(
          name: 'Renamed',
          urlTemplate: 'https://opac.example.fr/?q={ean13}',
        ),
      );

      final reloaded = await load();
      expect(reloaded.myLibraryPortals, hasLength(1));
      expect(reloaded.myLibraryPortals.single.name, 'Mediatheque test');
    });

    test('corrupt stored JSON degrades to an empty list', () async {
      SharedPreferences.setMockInitialValues({
        'my_bookshop_ids': 'not json',
        'my_library_portals': '[{"name":"x"}]',
      });
      final provider = await load();
      expect(provider.myBookshopIds, isEmpty);
      expect(provider.myLibraryPortals, isEmpty);
    });

    test('librarian and bookseller presets switch suggestions off, '
        'reader switches them back on', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await load();
      await provider.applyPreset('librarian');
      expect(provider.showBookshopFinder, isFalse);
      await provider.applyPreset('reader');
      expect(provider.showBookshopFinder, isTrue);
      await provider.applyPreset('bookseller');
      expect(provider.showBookshopFinder, isFalse);
    });
  });
}
