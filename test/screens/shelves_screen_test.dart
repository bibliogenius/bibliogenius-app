import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/organize_shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/shelf_tree_rows.dart';

/// The shelves tab tree: what a shelf row tells the reader, what its tap
/// does, and when the tree reloads.
///
/// The tab used to load its tags once and never again while its tab stayed
/// mounted, so a shelf created from a book form showed up only after leaving
/// the tab. And a delete "succeeded" while the shelf stayed on screen: the
/// name lived on in the books' subjects and came back as a synthetic orphan
/// the next delete could not reach.

class _RecordingTagRepository implements TagRepository {
  List<Tag> tags;
  final List<Tag> deleted = [];
  int reads = 0;
  int unshelved = 0;
  bool failReads = false;
  bool failDeletes = false;

  _RecordingTagRepository(this.tags);

  @override
  Future<List<Tag>> getTags() async {
    reads++;
    if (failReads) throw Exception(_raw);
    return tags;
  }

  @override
  Future<int> countUnshelvedBooks() async => unshelved;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async =>
      Tag(id: 'new', name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async {
    final renamed = Tag(id: uuid, name: name, parentId: parentId, count: 0);
    tags = [
      for (final t in tags)
        t.id == uuid
            ? Tag(id: uuid, name: name, parentId: parentId, count: t.count)
            : t,
    ];
    return renamed;
  }

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {
    if (failDeletes) throw Exception(_raw);
    deleted.add(tag);
    tags = tags.where((t) => t.id != tag.id).toList();
  }
}

/// What the core says when a call fails: never for the reader's eyes.
const _raw = 'database is locked';

const _catalogue = {
  'en': {
    'error_loading_page': 'Error loading page',
    'error_generic': 'An error occurred',
    'retry': 'Retry',
    'shelves': 'Shelves',
    'all_shelves': 'All shelves',
    'book': 'book',
    'books': 'books',
    'shelf_actions_named': 'Actions for {name}',
    'move_shelf_named': 'Move {name}',
    'shelf_collapse_named': 'Collapse {name}',
    'shelf_expand_named': 'Expand {name}',
    'sub_shelves_count': '%d sub-shelf',
    'sub_shelves_count_plural': '%d sub-shelves',
    'displayed_books_count': '%d book',
    'displayed_books_count_plural': '%d books',
    'shelf_deleted': 'Shelf "%s" deleted.',
    'delete_shelf': 'Delete shelf',
    'delete_shelf_confirm': 'Delete "%s"?',
    'delete_shelf_books_kept': 'The books stay in your library.',
    'delete': 'Delete',
    'cancel': 'Cancel',
    'edit_shelf': 'Edit',
    'update': 'Update',
    'shelf_name': 'Shelf name',
    'shelf_updated': 'Shelf updated',
    'action_undo': 'Undo',
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
  final navigated = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
    repo = _RecordingTagRepository([_genre, _roman, _polar, _orphan]);
    bookRefresh = BookRefreshNotifier();
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
              const OrganizeShelvesScreen(),
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

    // Spelled out under the name, and the sub-shelves fold the branch. The book
    // number is the whole subtree.
    expect(find.text('5 books'), findsOneWidget);
    expect(find.text('2 sub-shelves'), findsOneWidget);
    // Leaves keep the plain book count.
    expect(find.text('3 books'), findsOneWidget);
    expect(find.text('1 book'), findsOneWidget);
  });

  testWidgets('a parent shelf shows its sub-shelves under it, and its tap '
      'opens the books of the whole shelf', (tester) async {
    await pump(tester);

    // No descent: the sub-shelves are already in sight.
    expect(find.text('Roman'), findsOneWidget);
    expect(find.text('Polar'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Roman')).dy,
      greaterThan(tester.getTopLeft(find.text('Genre')).dy),
    );

    await tester.tap(find.text('Genre'));
    await tester.pumpAndSettle();
    expect(navigated, ['/shelves?tag=Genre']);
  });

  testWidgets('tapping a leaf shelf opens its books', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Thriller'));
    await tester.pumpAndSettle();

    expect(navigated, ['/shelves?tag=Thriller']);
  });

  testWidgets('deleting a shelf goes through deleteShelf and the tree '
      'reloads at once', (tester) async {
    await pump(tester);

    // The orphan has no `tags` row: the old uuid-only path silently skipped it
    // and reported success while the row stayed on screen.
    await tester.tap(find.byTooltip('Actions for Thriller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf'));
    await tester.pumpAndSettle();
    // Gone from the tree at once; the write waits on the Undo message.
    expect(find.text('Thriller'), findsNothing);
    expect(repo.deleted, isEmpty);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(repo.deleted.map((t) => t.name), ['Thriller']);
    expect(find.text('Thriller'), findsNothing);
  });

  /// Presses [key] until the focus sits on the control showing [target].
  Future<void> moveFocusTo(
    WidgetTester tester,
    Finder target,
    LogicalKeyboardKey key,
  ) async {
    bool focused() {
      final node = FocusManager.instance.primaryFocus;
      // A scope holds the whole menu or dialog: not yet one control.
      if (node == null || node is FocusScopeNode) return false;
      return find
          .descendant(
            of: find.byElementPredicate((e) => e == node.context),
            matching: target,
          )
          .evaluate()
          .isNotEmpty;
    }

    for (var i = 0; i < 10 && !focused(); i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(focused(), isTrue, reason: 'the keyboard reaches $target');
  }

  // The row was keyed by its name: a rename built a new one, and the focus
  // the dialog handed back went to a node that no longer existed.
  testWidgets('a rename from the keyboard leaves the focus on the renamed '
      'row', (tester) async {
    await pump(tester);
    final menu = find.descendant(
      of: find.byTooltip('Actions for Roman'),
      matching: find.byIcon(Icons.more_vert),
    );
    Focus.of(tester.element(menu)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await moveFocusTo(tester, find.text('Edit'), LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // The name field has the focus: typing replaces the name.
    await tester.enterText(find.byType(TextFormField), 'Romans');
    await moveFocusTo(tester, find.text('Update'), LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Romans'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    final row = focused!.findAncestorWidgetOfExactType<ShelfTreeRow>();
    expect(row?.name, 'Romans', reason: 'the focus stays on its row');
  });

  testWidgets('a tree that cannot load says so in a sentence', (tester) async {
    repo.failReads = true;
    await pump(tester);

    expect(find.text('Error loading page'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining(_raw), findsNothing);
  });

  testWidgets('a deletion that fails says so in a sentence, and the shelf '
      'comes back', (tester) async {
    await pump(tester);
    repo.failDeletes = true;

    await tester.tap(find.byTooltip('Actions for Thriller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('An error occurred'), findsOneWidget);
    expect(find.textContaining(_raw), findsNothing);
    expect(find.text('Thriller'), findsOneWidget);
  });

  testWidgets('a book change elsewhere reloads the tree and keeps what the '
      'reader folded', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Collapse Genre'));
    await tester.pumpAndSettle();
    expect(find.text('Roman'), findsNothing);
    final readsBefore = repo.reads;

    // A book form filed a book under a new sub-genre while this tab stayed
    // mounted behind it.
    repo.tags = [
      ...repo.tags,
      Tag(id: 'sf', name: 'Science-fiction', parentId: 'g', count: 1),
      Tag(id: 'c', name: 'Comics', count: 1),
    ];
    bookRefresh.refresh();
    await tester.pumpAndSettle();

    expect(repo.reads, greaterThan(readsBefore));
    expect(find.text('Comics'), findsOneWidget);
    // Genre stays folded: a data refresh must not undo what the reader
    // chose to hide.
    expect(find.text('Science-fiction'), findsNothing);
    expect(find.byTooltip('Expand Genre'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand Genre'));
    await tester.pumpAndSettle();
    expect(find.text('Science-fiction'), findsOneWidget);
  });
}
