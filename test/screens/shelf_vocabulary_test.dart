import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/shelf_management_screen.dart';
import 'package:bibliogenius/screens/shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';

/// The words the shelves surfaces use.
///
/// Readers could not tell a shelf from a collection: no screen said when to
/// take one rather than the other. The empty shelves tab now says it in two
/// sentences and a rule. And the top of the tree had three names ("None (root
/// level)", "Root Level (No Parent)", "Root (no parent)") for one place: every
/// surface now reads the single `first_level` key.

class _StaticTagRepository implements TagRepository {
  final List<Tag> tags;

  _StaticTagRepository(this.tags);

  @override
  Future<List<Tag>> getTags() async => tags;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async =>
      Tag(id: 'new', name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      Tag(id: uuid, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {}
}

const _shelfConcept =
    'Shelf: where you put a book. By theme, by room, by genre. A book can '
    'sit on several shelves, and a shelf can hold other shelves.';
const _collectionConcept =
    'Collection: a list of books that belong together, in an order. The '
    'volumes of a series, a selection to lend, your favorites.';
const _rule = 'Does the order matter? A collection. Otherwise, a shelf.';

const _catalogue = {
  'en': {
    'no_shelves_title': 'No shelves yet',
    'create_first_shelf': 'Create a shelf',
    'shelf_concept': _shelfConcept,
    'collection_concept': _collectionConcept,
    'shelf_or_collection_rule': _rule,
    'first_level': 'First level',
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
    'edit_shelf': 'Edit',
    'shelf_name': 'Shelf name',
    'parent_shelf': 'Parent shelf (optional)',
    'move_shelf': 'Move shelf',
    'move_shelf_hint': 'Change parent shelf',
    'delete_shelf': 'Delete shelf',
    'scan_into_shelf': 'Scan into this shelf',
    'cancel': 'Cancel',
    'save': 'Save',
    'back': 'Back',
    'view': 'View',
  },
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    List<Tag> tags,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
          Provider<TagRepository>.value(value: _StaticTagRepository(tags)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget shelvesTab() =>
      ShelvesScreen(isTabView: true, refreshNotifier: ValueNotifier<int>(0));

  testWidgets('the empty shelves tab tells a shelf from a collection', (
    tester,
  ) async {
    await pumpScreen(tester, shelvesTab(), const []);

    expect(find.text('No shelves yet'), findsOneWidget);
    expect(find.text(_shelfConcept), findsOneWidget);
    expect(find.text(_collectionConcept), findsOneWidget);
    expect(find.text(_rule), findsOneWidget);
  });

  testWidgets('the empty shelves tab scrolls instead of overflowing on a '
      'phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, shelvesTab(), const []);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    await tester.scrollUntilVisible(find.text(_rule), 200);
    expect(find.text(_rule), findsOneWidget);
  });

  testWidgets('the edit dialog of the tab names the top "First level"', (
    tester,
  ) async {
    await pumpScreen(tester, shelvesTab(), [
      Tag(id: 'g', name: 'Genre', count: 0),
      Tag(id: 'r', name: 'Roman', parentId: 'g', count: 3),
    ]);

    final card = find.ancestor(
      of: find.text('Genre'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    // Genre sits at the top, so the parent field shows the first-level entry.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('First level'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the move dialog of the management screen names the top '
      '"First level"', (tester) async {
    await pumpScreen(tester, const ShelfManagementScreen(), [
      Tag(id: 'g', name: 'Genre', count: 0),
      Tag(id: 'r', name: 'Roman', parentId: 'g', count: 3),
    ]);

    final row = find
        .ancestor(of: find.text('Roman'), matching: find.byType(InkWell))
        .first;
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('Change parent shelf'), findsOneWidget);
    await tester.tap(find.text('Move shelf'));
    await tester.pumpAndSettle();

    expect(find.text('First level'), findsOneWidget);
  });
}
