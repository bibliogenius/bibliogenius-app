import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/hierarchical_tag_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTagRepository implements TagRepository {
  final List<Tag> tags = [Tag(id: 'living', name: 'Living room', count: 0)];
  final List<String?> createdParents = [];

  @override
  Future<List<Tag>> getTags() async => List.of(tags);

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    createdParents.add(parentId);
    final tag = Tag(id: 'new-$name', name: name, parentId: parentId, count: 0);
    tags.add(tag);
    return tag;
  }

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteTag(String uuid) async => throw UnimplementedError();

  @override
  Future<void> deleteShelf(Tag tag) async => throw UnimplementedError();

  @override
  Future<int> countUnshelvedBooks() async => 0;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'tags_label': 'Shelves',
        'add_tag': 'Add',
        'search_or_create_shelf_hint': 'Search or create a shelf',
        'create_shelf_named': 'Create “{name}”',
        'create_shelf_inside': 'Create in a shelf…',
        'create_shelf_in_title': 'Create “{name}” in…',
        'create_shelf_first_level_instead': 'At the first level instead',
      },
    });
  });

  Future<_RecordingTagRepository> pumpAndType(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _RecordingTagRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HierarchicalTagSelector(
              selectedTags: const [],
              onTagsChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search or create a shelf'),
      'Night',
    );
    await tester.pumpAndSettle();
    return repo;
  }

  // The first level used to be unreachable once a parent had been offered:
  // `PopupMenuButton` reports a null value as a dismissal. The placement
  // tree that replaced the menu must keep the first level one tap away.
  testWidgets('the first level can still be picked from the placement tree', (
    tester,
  ) async {
    final repo = await pumpAndType(tester);

    await tester.tap(find.text('Create in a shelf…'));
    await tester.pumpAndSettle();
    expect(find.text('Create “Night” in…'), findsOneWidget);
    expect(find.text('Living room'), findsOneWidget);

    await tester.tap(find.text('At the first level instead'));
    await tester.pumpAndSettle();

    expect(repo.createdParents, [null], reason: 'created without a parent');
  });

  testWidgets('a shelf picked in the placement tree becomes the parent', (
    tester,
  ) async {
    final repo = await pumpAndType(tester);

    await tester.tap(find.text('Create in a shelf…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();

    expect(repo.createdParents, ['living']);
  });
}
