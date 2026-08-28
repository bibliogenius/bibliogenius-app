import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/bookshop_finder_card.dart';

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
    tempRoot = Directory.systemTemp.createTempSync('bookshop_card_test_');
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
    dotenv.testLoad();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'bookshop_finder_title': 'Find it at an independent bookshop',
        'bookshop_finder_hint': 'Check availability at bookshops near you.',
        'bookshop_finder_dismiss': "I don't want to see this",
        'bookshop_finder_configure': 'Choose my bookshops',
        'opens_external_site': 'Opens an external website',
      },
    });
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({'country': 'FR', ...prefs});
    final provider = ThemeProvider();
    await provider.loadSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: Scaffold(
            body: SingleChildScrollView(
              child: BookshopFinderCard(
                book: Book(title: 'Test book', isbn: '9782072895098'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the country default portal out of the box', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('Find it at an independent bookshop'), findsOneWidget);
    expect(find.text('Place des libraires'), findsOneWidget);
  });

  testWidgets('renders nothing once dismissed', (tester) async {
    await pumpCard(tester, prefs: {'bookshop_finder_dismissed': true});
    expect(find.text('Find it at an independent bookshop'), findsNothing);
  });

  testWidgets('the reader selection replaces the country defaults', (
    tester,
  ) async {
    await pumpCard(tester, prefs: {'my_bookshop_ids': '["leslibraires-fr"]'});
    expect(find.text('Les Libraires'), findsOneWidget);
    expect(find.text('Place des libraires'), findsNothing);
  });

  testWidgets('hand-added bookshops show and suppress the defaults', (
    tester,
  ) async {
    await pumpCard(
      tester,
      prefs: {
        'my_custom_bookshops':
            '[{"name":"Ma librairie","url_template":"https://shop.example.fr/?q={ean13}"}]',
      },
    );
    expect(find.text('Ma librairie'), findsOneWidget);
    expect(find.text('Place des libraires'), findsNothing);
  });
}
