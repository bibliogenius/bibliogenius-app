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

/// Typing an author's name is enough: the "+" button is a shortcut for
/// chaining several authors, not a required step. A name left in the field
/// becomes an author when the field loses focus, and in any case on save.
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
    TranslationService.setPoTranslationsForTest({
      'en': {'author_added_announcement': 'Author added: {name}'},
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

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

  Finder authorField() => find.byKey(const Key('authorField'));

  Future<void> typeAuthor(WidgetTester tester, String name) async {
    await tester.tap(authorField());
    await tester.enterText(authorField(), name);
    await tester.pump();
  }

  Future<void> saveAdd(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('saveBookButton')).first);
    await tester.tap(find.byKey(const Key('saveBookButton')).first);
    await tester.pumpAndSettle();
  }

  group('add form', () {
    setUp(() => bookRepo = MockBookRepository());

    Future<void> pumpAdd(WidgetTester tester) async {
      await pump(tester, const AddBookScreen());
      await tester.enterText(
        find.byKey(const Key('titleField')),
        'Les Misérables',
      );
      // Save stays disabled while the title search runs: let it finish.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
    }

    testWidgets('a typed author is saved without pressing +', (tester) async {
      await pumpAdd(tester);
      await typeAuthor(tester, 'Victor Hugo');

      await saveAdd(tester);

      expect(bookRepo.lastCreate?['author'], 'Victor Hugo');
    });

    testWidgets('an author added with + is saved', (tester) async {
      await pumpAdd(tester);
      await typeAuthor(tester, 'Victor Hugo');
      await tester.tap(
        find.descendant(of: authorField(), matching: find.byIcon(Icons.add)),
      );
      await tester.pump();

      await saveAdd(tester);

      expect(bookRepo.lastCreate?['author'], 'Victor Hugo');
    });

    testWidgets('leaving the field turns the typed name into an author', (
      tester,
    ) async {
      await pumpAdd(tester);
      await typeAuthor(tester, 'Victor Hugo');

      await tester.tap(find.byKey(const Key('titleField')));
      await tester.pump();

      expect(find.widgetWithText(Chip, 'Victor Hugo'), findsOneWidget);
      // The field empties itself: a screen reader must hear where the name went.
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Author added: Victor Hugo'),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: authorField(),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
    });
  });

  group('edit form', () {
    testWidgets('leaving the field turns the typed name into an author', (
      tester,
    ) async {
      bookRepo = MockBookRepository()
        ..mockBook = Book(id: 'book-uuid', title: 'Astérix', owned: true);
      await pump(tester, EditBookScreen(book: bookRepo.mockBook!));
      await typeAuthor(tester, 'René Goscinny');

      // The title field comes first in the form.
      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();

      expect(find.widgetWithText(Chip, 'René Goscinny'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(bookRepo.lastUpdate?['author'], 'René Goscinny');
    });
  });
}
