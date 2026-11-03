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

/// Deleting a shelf has one rule, whichever screen it starts from: the books
/// stay, the sub-shelves move up one level. The management screen used to
/// delete the whole subtree from Dart while the shelves tab let the core move
/// the children to the root: same word, two results, two different warnings.

class _RecordingTagRepository implements TagRepository {
  List<Tag> tags;
  final List<String> deleted = [];

  _RecordingTagRepository(this.tags);

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
  Future<void> deleteShelf(Tag tag) async {
    deleted.add(tag.name);
    tags = tags.where((t) => t.id != tag.id).toList();
  }

  @override
  Future<int> countUnshelvedBooks() async => 0;
}

const _catalogue = {
  'en': {
    'delete_shelf': 'Delete shelf',
    'delete_shelf_confirm': 'Delete "%s"?',
    'delete_shelf_books_kept': 'The books stay in your library.',
    'delete_shelf_children_moved_up': 'Its sub-shelf moves up one level.',
    'delete_shelf_children_moved_up_plural':
        'Its %d sub-shelves move up one level.',
    'delete': 'Delete',
    'cancel': 'Cancel',
    'shelf_actions_named': 'Actions for {name}',
    'move_shelf_named': 'Move {name}',
    'shelf_collapse_named': 'Collapse {name}',
    'shelf_expand_named': 'Expand {name}',
    'sub_shelves_count': '%d sub-shelf',
    'sub_shelves_count_plural': '%d sub-shelves',
    'displayed_books_count': '%d book',
    'displayed_books_count_plural': '%d books',
    'shelves': 'Shelves',
    'all_shelves': 'All shelves',
    'book': 'book',
    'books': 'books',
    'back': 'Back',
    'view': 'View',
    'edit_shelf': 'Edit',
    'scan_into_shelf': 'Scan into this shelf',
  },
};

List<Tag> _tree() => [
  Tag(id: 'g', name: 'Genre', count: 0),
  Tag(id: 'r', name: 'Roman', parentId: 'g', count: 3),
  Tag(id: 'p', name: 'Polar', parentId: 'g', count: 2),
];

/// Every text of the open dialog, in reading order.
List<String> _dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    TagRepository repo,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<String>> openDeleteFromShelvesTab(
    WidgetTester tester,
    _RecordingTagRepository repo,
  ) async {
    await pumpScreen(
      tester,
      ShelvesScreen(isTabView: true, refreshNotifier: ValueNotifier<int>(0)),
      repo,
    );
    await tester.tap(find.byTooltip('Actions for Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf'));
    await tester.pumpAndSettle();
    return _dialogTexts(tester);
  }

  Future<List<String>> openDeleteFromManagement(
    WidgetTester tester,
    _RecordingTagRepository repo,
  ) async {
    await pumpScreen(tester, const ShelfManagementScreen(), repo);
    final row = find
        .ancestor(of: find.text('Genre'), matching: find.byType(InkWell))
        .first;
    await tester.longPress(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf').last);
    await tester.pumpAndSettle();
    return _dialogTexts(tester);
  }

  const expectedBody =
      'Delete "Genre"?\n\n'
      'The books stay in your library.\n\n'
      'Its 2 sub-shelves move up one level.';

  testWidgets('the shelves tab states the one deletion rule', (tester) async {
    final repo = _RecordingTagRepository(_tree());
    final texts = await openDeleteFromShelvesTab(tester, repo);

    expect(texts, contains(expectedBody));
  });

  testWidgets('the management screen states the same rule, word for word', (
    tester,
  ) async {
    final repo = _RecordingTagRepository(_tree());
    final texts = await openDeleteFromManagement(tester, repo);

    expect(texts, contains(expectedBody));
  });

  testWidgets('the management screen deletes the shelf alone, not its '
      'sub-shelves', (tester) async {
    final repo = _RecordingTagRepository(_tree());
    await openDeleteFromManagement(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['Genre']);
  });

  testWidgets('a shelf without sub-shelves says nothing about them', (
    tester,
  ) async {
    final repo = _RecordingTagRepository(_tree());
    await pumpScreen(
      tester,
      ShelvesScreen(isTabView: true, refreshNotifier: ValueNotifier<int>(0)),
      repo,
    );
    // Every level shows at once: Polar's row is in reach.
    await tester.tap(find.byTooltip('Actions for Polar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete shelf'));
    await tester.pumpAndSettle();

    expect(
      _dialogTexts(tester),
      contains('Delete "Polar"?\n\nThe books stay in your library.'),
    );
  });
}
