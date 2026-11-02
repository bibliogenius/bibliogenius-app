import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/genre_chips_selector.dart';
import 'package:bibliogenius/widgets/hierarchical_tag_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTagRepository implements TagRepository {
  final List<Tag> tags = [];
  int _nextId = 1;

  @override
  Future<List<Tag>> getTags() async => List.of(tags);

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    final tag = Tag(
      id: 'uuid-${_nextId++}',
      name: name,
      parentId: parentId,
      count: 0,
    );
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

/// Mirrors how `add_book_screen` owns the shelves: ONE final list, mutated in
/// place. That is the wiring the shelf section has to survive.
class _AddBookLikeHost extends StatefulWidget {
  const _AddBookLikeHost();

  @override
  State<_AddBookLikeHost> createState() => _AddBookLikeHostState();
}

class _AddBookLikeHostState extends State<_AddBookLikeHost> {
  final List<String> _selectedTags = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GenreChipsSelector(
          selectedShelves: _selectedTags,
          onShelvesChanged: (shelves) {
            setState(() {
              _selectedTags.clear();
              _selectedTags.addAll(shelves);
            });
          },
        ),
        HierarchicalTagSelector(
          genresShownAbove: true,
          selectedTags: List.of(_selectedTags),
          onTagsChanged: (tags) {
            setState(() {
              _selectedTags.clear();
              _selectedTags.addAll(tags);
            });
          },
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'genre_root': 'Genre',
        'genre_crime': 'Crime & thriller',
        'genre_picker_label': 'Genre',
        'genre_picker_helper': 'Suggested genres.',
        'genre_refine': 'Refine (optional)',
        'tags_label': 'Shelves',
        'tags_helper': 'Organise your books.',
        'add_tag': 'Add',
      },
    });
  });

  testWidgets('a genre picked from the chips shows once, and the shelf '
      'picker has it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          Provider<TagRepository>.value(value: _FakeTagRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _AddBookLikeHost()),
          ),
        ),
      ),
    );

    expect(find.text('Crime & thriller'), findsOneWidget);

    await tester.tap(find.text('Crime & thriller'));
    await tester.pumpAndSettle();

    // The lit genre chip already says the book is on that shelf: a second
    // chip in the shelf row would say it twice.
    expect(
      find.text('Crime & thriller'),
      findsOneWidget,
      reason: 'the suggestion chip only',
    );

    // Hidden from the row is not missing from the selection: the selector
    // must have received the genre, or the picker would show it unchecked
    // and "Done" would drop it from the book.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('shelfRow:Crime & thriller')),
      ),
      containsSemantics(isButton: true, hasCheckedState: true, isChecked: true),
    );
    handle.dispose();
  });
}
