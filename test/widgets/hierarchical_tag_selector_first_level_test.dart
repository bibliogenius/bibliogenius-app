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
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'tags_label': 'Shelves',
        'add_tag': 'Add',
        'create_new_tag': 'New shelf',
        'tag_name_hint': 'Shelf name',
        'first_level': 'First level',
      },
    });
  });

  // `PopupMenuButton` reports a null value as a dismissal, so the first-level
  // entry could never be picked back once a parent had been chosen.
  testWidgets('the first level can be picked again after a parent', (
    tester,
  ) async {
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
    await tester.tap(find.text('New shelf').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Shelf name'),
      'Night',
    );

    // Choose a parent ...
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room').last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);

    // ... then go back to the first level.
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First level').last);
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.subdirectory_arrow_right),
      findsNothing,
      reason: 'the chosen parent is cleared',
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(repo.createdParents, [null], reason: 'created without a parent');
  });
}
