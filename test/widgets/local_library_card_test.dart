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
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/local_library_card.dart';

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
    tempRoot = Directory.systemTemp.createTempSync('library_card_test_');
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
        'local_library_card_title': 'At your library',
        'library_intro_text': 'Borrow close to home too.',
        'settings_libraries_add': 'Connect my library',
        'bookshop_finder_dismiss': "I don't want to see this",
        'local_library_configure': 'Manage my library',
        'opens_external_site': 'Opens an external website',
        'card_hidden': 'Card hidden',
        'action_undo': 'Undo',
      },
    });
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final theme = ThemeProvider();
    await theme.loadSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            // Never loaded on purpose: no city, so the intro card starts
            // no lookup and the test stays offline.
            ChangeNotifierProvider<HubDirectoryProvider>(
              create: (_) => HubDirectoryProvider(),
            ),
          ],
          child: Scaffold(
            body: SingleChildScrollView(
              child: LocalLibraryCard(
                book: Book(title: 'Test book', isbn: '9782072895098'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the discoverable intro before any catalogue exists', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('At your library'), findsOneWidget);
    expect(find.text('Borrow close to home too.'), findsOneWidget);
    expect(find.text('Connect my library'), findsOneWidget);
  });

  testWidgets('the intro hides for non-borrowing profiles', (tester) async {
    await pumpCard(tester, prefs: {'canBorrowBooks': false});
    expect(find.text('At your library'), findsNothing);
  });

  testWidgets('the cross hides the intro and Undo restores it', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.tap(find.byTooltip("I don't want to see this"));
    await tester.pumpAndSettle();
    expect(find.text('At your library'), findsNothing);
    expect(find.text('Card hidden'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('At your library'), findsOneWidget);
  });

  testWidgets('the intro hides once dismissed', (tester) async {
    await pumpCard(tester, prefs: {'library_intro_dismissed': true});
    expect(find.text('At your library'), findsNothing);
  });

  testWidgets('a connected catalogue replaces the intro with its link', (
    tester,
  ) async {
    await pumpCard(
      tester,
      prefs: {
        'my_library_portals':
            '[{"name":"Mediatheque X","url_template":"https://opac.example.fr/?q={ean13}"}]',
        // The dismissed intro must NOT hide a connected catalogue.
        'library_intro_dismissed': true,
      },
    );
    expect(find.text('Mediatheque X'), findsOneWidget);
    expect(find.text('Borrow close to home too.'), findsNothing);
  });
}
