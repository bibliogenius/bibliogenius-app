import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/add_book_screen.dart';
import 'package:bibliogenius/screens/edit_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/translation_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// The publisher field suggests the publishers already in the library, in
/// the add and edit forms alike, and still saves a name typed freely.
class _QuietHubDirectoryProvider extends HubDirectoryProvider {
  @override
  void markCatalogDirty() {}

  @override
  Future<void> syncCatalogIfDirty() async {}
}

void main() {
  late MockBookRepository bookRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad();
    TranslationService.setPoTranslationsForTest({});
    bookRepo = MockBookRepository()
      ..mockBooks = [
        Book(title: 'Les Gommes', publisher: 'Éditions de Minuit'),
        Book(title: 'Vendredi', publisher: 'Gallimard'),
        Book(title: 'Le Petit Prince', publisher: 'Gallimard Jeunesse'),
      ];
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/form', builder: (_, _) => screen),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<HubDirectoryProvider>(
            create: (_) => _QuietHubDirectoryProvider(),
          ),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          Provider<BookRepository>.value(value: bookRepo),
          Provider<CollectionRepository>.value(
            value: MockCollectionRepository(),
          ),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          Provider<ApiService>.value(value: MockApiService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/form');
    await tester.pumpAndSettle();
  }

  Finder publisherField() => find.byKey(const Key('publisherField'));

  Future<void> typePublisher(WidgetTester tester, String text) async {
    // The form is a lazy list: the field is built once scrolled to.
    await tester.scrollUntilVisible(
      publisherField(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(publisherField());
    await tester.enterText(publisherField(), text);
    await tester.pumpAndSettle();
  }

  /// A suggestion in the options list: the tests type a text that differs
  /// from every name, so the name can only be a suggestion's.
  Finder suggestion(String name) => find.text(name);

  Future<void> pumpAdd(WidgetTester tester) async {
    await pump(tester, const AddBookScreen());
    await tester.enterText(find.byKey(const Key('titleField')), 'Vendredi');
    // Save stays disabled while the title search runs: let it finish.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Future<void> saveAdd(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('saveBookButton')).first);
    await tester.tap(find.byKey(const Key('saveBookButton')).first);
    await tester.pumpAndSettle();
  }

  group('add form', () {
    testWidgets('the publishers are read once, when the field is focused', (
      tester,
    ) async {
      await pumpAdd(tester);
      expect(bookRepo.calls, isNot(contains('getAllPublishers')));

      await typePublisher(tester, 'gall');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await typePublisher(tester, 'minuit');

      expect(bookRepo.calls.where((c) => c == 'getAllPublishers').length, 1);
    });

    testWidgets('suggests the library publishers matching the text', (
      tester,
    ) async {
      await pumpAdd(tester);
      await typePublisher(tester, 'gall');

      expect(suggestion('Gallimard'), findsOneWidget);
      expect(suggestion('Gallimard Jeunesse'), findsOneWidget);
      expect(suggestion('Éditions de Minuit'), findsNothing);
    });

    testWidgets('a tapped suggestion is saved as the publisher', (
      tester,
    ) async {
      await pumpAdd(tester);
      await typePublisher(tester, 'minuit');
      await tester.tap(suggestion('Éditions de Minuit'));
      await tester.pumpAndSettle();

      await saveAdd(tester);

      expect(bookRepo.lastCreate?['publisher'], 'Éditions de Minuit');
    });

    testWidgets('a publisher missing from the library is saved as typed', (
      tester,
    ) async {
      await pumpAdd(tester);
      await typePublisher(tester, 'Gallimard Loisirs');

      expect(suggestion('Gallimard'), findsNothing);
      await saveAdd(tester);

      expect(bookRepo.lastCreate?['publisher'], 'Gallimard Loisirs');
    });
  });

  group('edit form', () {
    testWidgets('a tapped suggestion is saved as the publisher', (
      tester,
    ) async {
      bookRepo.mockBook = Book(
        id: 'book-uuid',
        title: 'Vendredi',
        publisher: 'Folio',
        owned: true,
      );
      await pump(tester, EditBookScreen(book: bookRepo.mockBook!));
      await typePublisher(tester, 'jeun');
      await tester.tap(suggestion('Gallimard Jeunesse'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(bookRepo.lastUpdate?['publisher'], 'Gallimard Jeunesse');
    });
  });
}
