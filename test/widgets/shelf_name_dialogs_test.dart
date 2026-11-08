import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/utils/accessible_color.dart';
import 'package:bibliogenius/widgets/hierarchical_tag_selector.dart';
import 'package:bibliogenius/widgets/move_shelf_sheet.dart';
import 'package:bibliogenius/widgets/quick_actions_sheet.dart';
import 'package:bibliogenius/widgets/shelf_actions.dart';

/// The name of a shelf as the reader types it: at most 60 characters, a
/// longer one refused in words rather than cut, and a failed write told in a
/// sentence, never in the core's own error.

/// What the core says when a write fails: never for the reader's eyes.
const _raw = 'UNIQUE constraint failed: tags.name';

class _Repo implements TagRepository {
  List<Tag> tags;
  bool failWrites = false;
  final List<String> created = [];
  final List<String> renamed = [];

  _Repo(this.tags);

  @override
  Future<List<Tag>> getTags() async => List.of(tags);

  @override
  Future<int> countUnshelvedBooks() async => 0;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    if (failWrites) throw Exception(_raw);
    created.add(name);
    final tag = Tag(id: 'new-$name', name: name, parentId: parentId, count: 0);
    tags = [...tags, tag];
    return tag;
  }

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async {
    if (failWrites) throw Exception(_raw);
    renamed.add(name);
    return Tag(id: uuid, name: name, parentId: parentId, count: 0);
  }

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {}
}

const _catalogue = {
  'en': {
    'shelf_name': 'Shelf name',
    'shelf_name_hint': 'e.g. Science fiction',
    'create_shelf': 'Create a shelf',
    'edit_shelf': 'Edit',
    'create': 'Create',
    'update': 'Update',
    'cancel': 'Cancel',
    'field_required': 'Required',
    'shelf_already_exists': 'This shelf already exists',
    'shelf_name_too_long': 'A shelf name has %d characters at most.',
    'tag_creation_error': 'Error creating shelf',
    'error_update': 'Update failed',
    'shelf_created': 'Shelf created',
    'shelf_updated': 'Shelf updated',
    'shelf_moved_under': '{name} moved under {parent}',
    'shelf_moved_to_first_level': '{name} moved to the first level',
    'first_level': 'First level',
    'parent_shelf': 'Parent shelf',
    'tags_label': 'Shelves',
    'add_tag': 'Add',
    'search_or_create_shelf_hint': 'Search or create a shelf',
    'create_shelf_named': 'Create “{name}”',
    'create_shelf_inside': 'Create in a shelf…',
    'done': 'Done',
    'action_undo': 'Undo',
  },
};

final _tooLongMessage = find.text('A shelf name has 60 characters at most.');

String _name(int length) => 'n' * length;

/// The bar carrying [text], whose text must read on its ground in [theme].
void _expectReadableBar(WidgetTester tester, String text, ThemeData theme) {
  final bar = tester.widget<SnackBar>(
    find.ancestor(of: find.text(text), matching: find.byType(SnackBar)),
  );
  // The theme's own bar, vetted for its text, not a hard-coded red or green.
  expect(bar.backgroundColor, isNull);
  expect(
    contrastRatio(
      theme.colorScheme.inverseSurface,
      theme.colorScheme.onInverseSurface,
    ),
    greaterThanOrEqualTo(4.5),
  );
}

void main() {
  late _Repo repo;
  late BuildContext host;

  setUpAll(ThemeRegistry.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest(_catalogue);
    repo = _Repo([Tag(id: 'living', name: 'Living room', count: 0)]);
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpHost(
    WidgetTester tester, {
    Widget? body,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                host = context;
                return body ?? const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
  }

  Finder field() => find.byType(TextFormField);

  group('creating a shelf', () {
    Future<void> openCreate(WidgetTester tester) async {
      await pumpHost(tester);
      showNewShelfDialog(host, shownTags: repo.tags, onCreated: () {});
      await tester.pumpAndSettle();
    }

    testWidgets('61 characters are refused in words, and nothing is created', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.enterText(field(), _name(61));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(_tooLongMessage, findsOneWidget);
      // Not cut to fit: the reader decides what to drop.
      expect(find.text(_name(61)), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('60 characters are a name', (tester) async {
      await openCreate(tester);
      await tester.enterText(field(), _name(60));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(repo.created, [_name(60)]);
    });

    testWidgets('a failed write says so in a sentence', (tester) async {
      await openCreate(tester);
      repo.failWrites = true;
      await tester.enterText(field(), 'Attic');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Error creating shelf'), findsOneWidget);
      expect(find.textContaining('UNIQUE'), findsNothing);
    });
  });

  group('renaming a shelf', () {
    final long = Tag(id: 'long', name: _name(70), count: 1);

    Future<void> openRename(WidgetTester tester, Tag tag) async {
      repo.tags = [...repo.tags, tag];
      await pumpHost(tester);
      showRenameShelfDialog(
        host,
        tag: tag,
        allTags: repo.tags,
        onRenamed: (_) {},
        onUndone: () {},
        onUndoShown: (_) {},
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a longer name already there is shown whole, kept whole while '
        'edited, and refused in words', (tester) async {
      await openRename(tester, long);
      expect(find.text(_name(70)), findsOneWidget);

      // One character off: still over, and still not cut to 60.
      await tester.enterText(field(), _name(69));
      await tester.pump();
      expect(find.text(_name(69)), findsOneWidget);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(_tooLongMessage, findsOneWidget);
      expect(repo.renamed, isEmpty);
    });

    testWidgets('brought down to 60, it is saved', (tester) async {
      await openRename(tester, long);
      await tester.enterText(field(), _name(60));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(repo.renamed, [_name(60)]);
    });

    testWidgets('a failed write says so in a sentence', (tester) async {
      await openRename(tester, Tag(id: 'a', name: 'Attic', count: 1));
      repo.failWrites = true;
      await tester.enterText(field(), 'Cellar');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(find.text('Update failed'), findsOneWidget);
      expect(find.textContaining('UNIQUE'), findsNothing);
    });
  });

  for (final style in const ['default', 'dark', 'minimal']) {
    testWidgets('$style: a failed Undo of a rename says so on a readable '
        'bar', (tester) async {
      final theme = ThemeRegistry.get(
        style,
      )!.buildTheme(accentColor: Colors.blue);
      final attic = Tag(id: 'a', name: 'Attic', count: 1);
      repo.tags = [...repo.tags, attic];
      await pumpHost(tester, theme: theme);
      showRenameShelfDialog(
        host,
        tag: attic,
        allTags: repo.tags,
        onRenamed: (_) {},
        onUndone: () {},
        onUndoShown: (_) {},
      );
      await tester.pumpAndSettle();
      await tester.enterText(field(), 'Cellar');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      repo.failWrites = true;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('UNIQUE'), findsNothing);
      _expectReadableBar(tester, 'Update failed', theme);
    });
  }

  testWidgets('a failed move says so in a sentence', (tester) async {
    await pumpHost(tester);
    repo.failWrites = true;
    final moved = moveShelf(
      host,
      shelf: Tag(id: 'a', name: 'Attic', count: 1),
      parent: repo.tags.first,
    );
    await tester.pumpAndSettle();

    expect(await moved, isFalse);
    expect(find.text('Update failed'), findsOneWidget);
    expect(find.textContaining('UNIQUE'), findsNothing);
  });

  group('the quick action that creates a shelf', () {
    Future<void> openQuick(WidgetTester tester) async {
      await pumpHost(tester);
      QuickActionsSheet.showCreateShelfDialog(host, null);
      await tester.pumpAndSettle();
    }

    testWidgets('refuses 61 characters in words', (tester) async {
      await openQuick(tester);
      await tester.enterText(field(), _name(61));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(_tooLongMessage, findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('says a failed write in a sentence', (tester) async {
      // The dialog closes the sheet it came from: give it one to close.
      await pumpHost(tester);
      Navigator.of(host).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('sheet')),
        ),
      );
      await tester.pumpAndSettle();
      QuickActionsSheet.showCreateShelfDialog(
        tester.element(find.text('sheet')),
        null,
      );
      await tester.pumpAndSettle();
      repo.failWrites = true;
      await tester.enterText(field(), 'Attic');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Error creating shelf'), findsOneWidget);
      expect(find.textContaining('UNIQUE'), findsNothing);
      _expectReadableBar(tester, 'Error creating shelf', ThemeData());
    });

    testWidgets('says a success on a readable bar', (tester) async {
      await pumpHost(tester);
      Navigator.of(host).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('sheet')),
        ),
      );
      await tester.pumpAndSettle();
      QuickActionsSheet.showCreateShelfDialog(
        tester.element(find.text('sheet')),
        null,
      );
      await tester.pumpAndSettle();
      await tester.enterText(field(), 'Attic');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(repo.created, ['Attic']);
      _expectReadableBar(tester, 'Shelf created', ThemeData());
    });
  });

  group('the shelf picker of a book', () {
    Future<void> pumpAndType(WidgetTester tester, String text) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpHost(
        tester,
        body: HierarchicalTagSelector(
          selectedTags: const [],
          onTagsChanged: (_) {},
        ),
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search or create a shelf'),
        text,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers no shelf of 61 characters, and says why', (
      tester,
    ) async {
      await pumpAndType(tester, _name(61));

      expect(find.text('Create “${_name(61)}”'), findsNothing);
      expect(find.text('Create in a shelf…'), findsNothing);
      expect(_tooLongMessage, findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
    });

    testWidgets('still offers 60 characters', (tester) async {
      await pumpAndType(tester, _name(60));

      expect(find.text('Create “${_name(60)}”'), findsOneWidget);
      expect(_tooLongMessage, findsNothing);
    });
  });
}
