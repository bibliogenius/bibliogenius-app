import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';

/// The shelves grid: what a shelf card tells the reader, what its tap does,
/// and when the grid reloads.
///
/// The grid used to load its tags once and never again while its tab stayed
/// mounted, so a shelf created from a book form showed up only after leaving
/// the tab. And a delete "succeeded" while the shelf stayed on screen: the
/// name lived on in the books' subjects and came back as a synthetic orphan
/// the next delete could not reach.

class _RecordingTagRepository implements TagRepository {
  List<Tag> tags;
  final List<Tag> deleted = [];
  int reads = 0;
  int unshelved = 0;

  _RecordingTagRepository(this.tags);

  @override
  Future<List<Tag>> getTags() async {
    reads++;
    return tags;
  }

  @override
  Future<int> countUnshelvedBooks() async => unshelved;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async =>
      Tag(id: 'new', name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      Tag(id: uuid, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {
    deleted.add(tag);
    tags = tags.where((t) => t.id != tag.id).toList();
  }
}

const _catalogue = {
  'en': {
    'shelves': 'Shelves',
    'all_shelves': 'All shelves',
    'book': 'book',
    'books': 'books',
    'view_shelf_books': 'View books',
    'sub_shelves_count': '%d sub-shelf',
    'sub_shelves_count_plural': '%d sub-shelves',
    'displayed_books_count': '%d book',
    'displayed_books_count_plural': '%d books',
    'displayed_shelves_count': '%d shelf',
    'displayed_shelves_count_plural': '%d shelves',
    'shelf_deleted': 'Shelf "%s" deleted.',
    'delete_shelf': 'Delete shelf',
    'delete_shelf_confirm': 'Delete "%s"?',
    'delete_shelf_books_kept': 'The books stay in your library.',
    'delete': 'Delete',
    'cancel': 'Cancel',
    'edit_shelf': 'Edit',
    'scan_into_shelf': 'Scan into this shelf',
    'back': 'Back',
    'view': 'View',
    'to_shelve_title': 'To shelve',
    'to_shelve_count': '%d book on no shelf',
    'to_shelve_count_plural': '%d books on no shelf',
  },
};

final _genre = Tag(id: 'g', name: 'Genre', count: 0);
final _roman = Tag(id: 'r', name: 'Roman', parentId: 'g', count: 3);
final _polar = Tag(id: 'p', name: 'Polar', parentId: 'g', count: 2);
final _orphan = Tag(id: 'legacy:-1', name: 'Thriller', count: 1);

void main() {
  late _RecordingTagRepository repo;
  late BookRefreshNotifier bookRefresh;
  late ValueNotifier<int> tabRefresh;
  final navigated = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
    repo = _RecordingTagRepository([_genre, _roman, _polar, _orphan]);
    bookRefresh = BookRefreshNotifier();
    tabRefresh = ValueNotifier<int>(0);
    navigated.clear();
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              ShelvesScreen(isTabView: true, refreshNotifier: tabRefresh),
        ),
        GoRoute(
          path: '/shelves',
          builder: (_, state) {
            navigated.add(state.uri.toString());
            return const Scaffold(body: Text('books list'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<BookRefreshNotifier>.value(
            value: bookRefresh,
          ),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a parent shelf says how many sub-shelves it holds', (
    tester,
  ) async {
    await pump(tester);

    // The explicit affordance, not a bare chevron: the reader is told what
    // the tap opens. The book number is the whole subtree.
    expect(find.text('2 sub-shelves'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // Leaves keep the plain book count.
    expect(find.text('1 book'), findsOneWidget);
  });

  testWidgets('tapping a parent shelf opens its sub-shelves, never an empty '
      'book list', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Genre'));
    await tester.pumpAndSettle();

    expect(navigated, isEmpty);
    expect(find.text('Roman'), findsOneWidget);
    expect(find.text('Polar'), findsOneWidget);
    // The level header names where the reader is and offers the books of the
    // whole shelf, which is the only way to reach them from here.
    expect(find.text('View books'), findsOneWidget);
    await tester.tap(find.text('View books'));
    await tester.pumpAndSettle();
    expect(navigated, ['/shelves?tag=Genre']);
  });

  testWidgets('tapping a leaf shelf opens its books', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Thriller'));
    await tester.pumpAndSettle();

    expect(navigated, ['/shelves?tag=Thriller']);
  });

  testWidgets('deleting a shelf goes through deleteShelf and the grid '
      'reloads at once', (tester) async {
    await pump(tester);

    // The orphan has no `tags` row: the old uuid-only path silently skipped it
    // and reported success while the card stayed on screen.
    final card = find.ancestor(
      of: find.text('Thriller'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deleted.map((t) => t.name), ['Thriller']);
    expect(find.text('Thriller'), findsNothing);
  });

  testWidgets('a book change elsewhere reloads the grid and keeps the level', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Genre'));
    await tester.pumpAndSettle();
    final readsBefore = repo.reads;

    // A book form filed a book under a new sub-genre while this tab stayed
    // mounted behind it.
    repo.tags = [
      ...repo.tags,
      Tag(id: 'sf', name: 'Science-fiction', parentId: 'g', count: 1),
    ];
    bookRefresh.refresh();
    await tester.pumpAndSettle();

    expect(repo.reads, greaterThan(readsBefore));
    expect(find.text('Science-fiction'), findsOneWidget);
    // Still inside "Genre": a data refresh must not throw the reader back to
    // the root.
    expect(find.text('View books'), findsOneWidget);
  });

  // The "to shelve" card: the books on no shelf, gathered at the head of the
  // tab, the natural place to start after a batch scan.
  group('to shelve card', () {
    final card = find.byKey(const Key('toShelveCard'));

    testWidgets('is absent when every book is on a shelf', (tester) async {
      repo.unshelved = 0;
      await pump(tester);

      expect(card, findsNothing);
      expect(find.text('To shelve'), findsNothing);
    });

    testWidgets('announces the books on no shelf, as one button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      repo.unshelved = 23;
      await pump(tester);

      expect(card, findsOneWidget);
      expect(find.text('To shelve'), findsOneWidget);
      expect(find.text('23 books on no shelf'), findsOneWidget);
      expect(
        tester.getSemantics(card),
        containsSemantics(
          label: 'To shelve\n23 books on no shelf',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('uses the singular for one book', (tester) async {
      repo.unshelved = 1;
      await pump(tester);

      expect(find.text('1 book on no shelf'), findsOneWidget);
    });

    testWidgets('opens the list of those books, in the shelves tab, '
        'selection armed and scoped to the default view', (tester) async {
      repo.unshelved = 3;
      await pump(tester);

      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(navigated, ['/shelves?unshelved=1&select=1&owned=library']);
    });

    testWidgets('stays at the first level only', (tester) async {
      repo.unshelved = 3;
      await pump(tester);

      await tester.tap(find.text('Genre'));
      await tester.pumpAndSettle();

      expect(card, findsNothing);
    });

    testWidgets('is shown above the empty state too', (tester) async {
      // Ten books scanned, no shelf yet: the card is where shelving starts.
      repo
        ..tags = []
        ..unshelved = 10;
      await pump(tester);

      expect(card, findsOneWidget);
      expect(find.text('10 books on no shelf'), findsOneWidget);
    });

    testWidgets('follows a book change elsewhere, and disappears at zero', (
      tester,
    ) async {
      repo.unshelved = 2;
      await pump(tester);
      expect(card, findsOneWidget);

      repo.unshelved = 0;
      bookRefresh.refresh();
      await tester.pumpAndSettle();

      expect(card, findsNothing);
    });
  });

  testWidgets('the tab refresh notifier reloads the grid too', (tester) async {
    await pump(tester);
    final readsBefore = repo.reads;

    tabRefresh.value++;
    await tester.pumpAndSettle();

    expect(repo.reads, greaterThan(readsBefore));
  });
}
