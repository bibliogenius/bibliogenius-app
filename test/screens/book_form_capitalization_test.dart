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

/// On a phone keyboard, a field without `textCapitalization` starts in lower
/// case: every title and author typed on an iPhone needed a manual shift.
/// A title is a sentence (only its first word takes a capital, per French
/// typography), an author or a publisher is a proper name (every word).
/// The ISBN keeps the default: its only letter is a check digit X.
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
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    // The form is a lazy list: a tall surface builds every field at once.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

  TextCapitalization capitalizationOf(WidgetTester tester, Finder field) =>
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .textCapitalization;

  /// The edit form gives most fields no key: find them by what they hold.
  Finder fieldHolding(String text) => find.ancestor(
    of: find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == text,
    ),
    matching: find.byType(TextFormField),
  );

  group('add form', () {
    setUp(() => bookRepo = MockBookRepository());

    testWidgets('text fields capitalize, the ISBN does not', (tester) async {
      await pump(tester, const AddBookScreen());

      expect(
        capitalizationOf(tester, find.byKey(const Key('titleField'))),
        TextCapitalization.sentences,
      );
      expect(
        capitalizationOf(tester, find.byKey(const Key('authorField'))),
        TextCapitalization.words,
      );
      expect(
        capitalizationOf(tester, find.byKey(const Key('publisherField'))),
        TextCapitalization.words,
      );
      expect(
        capitalizationOf(tester, find.byKey(const Key('summaryField'))),
        TextCapitalization.sentences,
      );
      expect(
        capitalizationOf(tester, find.byKey(const Key('isbnField'))),
        TextCapitalization.none,
      );
    });
  });

  group('edit form', () {
    testWidgets('text fields capitalize, the ISBN does not', (tester) async {
      bookRepo = MockBookRepository()
        ..mockBook = Book(
          id: 'book-uuid',
          title: 'La Peste',
          publisher: 'Gallimard',
          summary: 'Une épidémie à Oran.',
          isbn: '9782070360420',
          owned: true,
        );
      await pump(tester, EditBookScreen(book: bookRepo.mockBook!));

      expect(
        capitalizationOf(tester, fieldHolding('La Peste')),
        TextCapitalization.sentences,
      );
      expect(
        capitalizationOf(tester, find.byKey(const Key('authorField'))),
        TextCapitalization.words,
      );
      expect(
        capitalizationOf(tester, fieldHolding('Gallimard')),
        TextCapitalization.words,
      );
      expect(
        capitalizationOf(tester, fieldHolding('Une épidémie à Oran.')),
        TextCapitalization.sentences,
      );
      expect(
        capitalizationOf(tester, fieldHolding('9782070360420')),
        TextCapitalization.none,
      );
    });
  });
}
