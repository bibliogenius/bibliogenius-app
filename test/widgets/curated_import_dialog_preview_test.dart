import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/curated_book_preview.dart';
import 'package:bibliogenius/widgets/curated_import_dialog.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// The pre-import dialog has to SHOW the list before it offers to import it.
///
/// It used to name a count and nothing else, which meant the ADR-066
/// suggestion card could put ten books into someone's library without ever
/// naming one of them. The catalogue, the surface the reader chose to open,
/// has listed them since it shipped.

class _ImportApi extends MockApiService {
    String? createdSource;

  @override
  Future<Collection> createCollection(
    String name, {
    String? description,
    String source = 'manual',
  }) async {
    createdSource = source;
    return Collection(
      id: 'c1',
      name: name,
      description: description,
      source: 'manual',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    );
  }
}

class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.inputs);

  final DiscoveryLookupInputs inputs;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => null;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

CuratedList _list({int books = 10}) => CuratedList(
  id: 'monde-100-livres',
  version: 1,
  title: const {'en': 'The 100 books of the century'},
  description: const {'en': ''},
  tags: const [],
  contentLanguages: const ['fr'],
  books: [
    for (var i = 0; i < books; i++)
      CuratedBook(isbn: '97800000000$i', note: 'Work $i - Author $i'),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'import_list_title': 'Import {title}',
        'import_list_desc': 'This list holds {count} books',
        'imported_books_status': 'Status',
        'curated_see_all_books': 'See the {count} books',
        'curated_see_less': 'See less',
        'cancel': 'Cancel',
        'import': 'Import',
        'catalog_already_in_library': 'Already in your library',
      },
    });
  });

  late BookRefreshNotifier refresh;

  Future<void> openDialog(
    WidgetTester tester,
    CuratedList list, {
    Set<String> ownedIsbns = const {},
  }) async {
    refresh = BookRefreshNotifier();
    final recommendations = RecommendationProvider(
      _FakeRepository(
        DiscoveryLookupInputs(
          series: const [],
          authors: const [],
          libraryIsbns: ownedIsbns,
          libraryTitleAuthorKeys: const {},
        ),
      ),
      BookRefreshNotifier(),
    );
    // Providers ABOVE MaterialApp: `showDialog` pushes its route at the root
    // navigator, so a provider scoped under `home:` is not in the dialog's
    // context and every lookup inside it throws.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<RecommendationProvider>.value(
            value: recommendations,
          ),
          Provider<TagRepository>.value(value: MockTagRepository()),
          ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
          Provider<ApiService>.value(value: _ImportApi()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CuratedImportDialog.show(context, list),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Bounded pumps: the dialog is opened behind an await and a
    // pumpAndSettle would hang on anything showing a progress indicator.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the dialog names the books, not just how many', (tester) async {
    await openDialog(tester, _list());

    expect(find.byType(CuratedBookPreview), findsOneWidget);
    expect(find.text('Work 0'), findsOneWidget);
    expect(find.text('Work 1'), findsOneWidget);
    expect(find.text('Work 2'), findsOneWidget);
  });

  testWidgets('the whole list is one tap away, without leaving the dialog', (
    tester,
  ) async {
    await openDialog(tester, _list());

    await tester.tap(find.text('See the 10 books'));
    await tester.pump();

    expect(find.text('Work 9'), findsOneWidget);
    // The commit controls survive the expansion: the reader can still act.
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the preview sits above the choices, so it is read first', (
    tester,
  ) async {
    await openDialog(tester, _list());

    final preview = tester.getTopLeft(find.byType(CuratedBookPreview)).dy;
    final status = tester.getTopLeft(find.text('Status')).dy;
    expect(preview, lessThan(status));
  });

  testWidgets('the books the reader already has are marked in the preview', (
    tester,
  ) async {
    // The dialog has always known how many books it would skip. Naming WHICH
    // ones is what turns a count into a decision.
    await openDialog(
      tester,
      _list(),
      ownedIsbns: const {'978000000000', '978000000002'},
    );

    expect(find.byTooltip('Already in your library'), findsNWidgets(2));
  });

  testWidgets('a library that overlaps nothing marks nothing', (tester) async {
    await openDialog(tester, _list(), ownedIsbns: const {'9789999999999'});

    expect(find.byTooltip('Already in your library'), findsNothing);
  });

  testWidgets('a finished import tells the app its catalogue moved', (
    tester,
  ) async {
    // Ten books and a collection appear, and nothing on screen knows. The
    // Collections page listens to BookRefreshNotifier, so the import owes it
    // a notification: without one the reader lands back on a list that does
    // not contain what they just imported, and has to leave the page and
    // come back for it to show up.
    var refreshes = 0;
    await openDialog(tester, _list(books: 2));
    refresh.addListener(() => refreshes++);

    await tester.tap(find.text('Import'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(refreshes, greaterThan(0));
  });
}
