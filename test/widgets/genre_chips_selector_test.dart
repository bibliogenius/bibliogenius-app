import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/genre_chips_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTagRepository implements TagRepository {
  final List<Tag> tags = [];
  final List<String> created = [];
  int _nextId = 1;

  @override
  Future<List<Tag>> getTags() async => List.of(tags);

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    created.add(name);
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
}

/// Holds the shelves the way the add/edit screens do, so a tap round-trips
/// through `onShelvesChanged` and back into the widget.
class _Host extends StatefulWidget {
  final List<String> initial;
  const _Host({this.initial = const []});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> shelves = List.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return GenreChipsSelector(
      selectedShelves: shelves,
      onShelvesChanged: (next) => setState(() => shelves = next),
    );
  }
}

void main() {
  late _RecordingTagRepository repo;
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    repo = _RecordingTagRepository();

    // English only: every locale falls back to it, so the test does not depend
    // on the provider's default language.
    TranslationService.setPoTranslationsForTest({
      'en': {
        'genre_root': 'Genre',
        'genre_crime': 'Crime & thriller',
        'genre_thriller': 'Thriller',
        'genre_noir': 'Noir',
        'genre_novel': 'Fiction',
        'genre_picker_label': 'Genre',
        'genre_picker_helper': 'Suggested genres.',
        'genre_refine': 'Refine (optional)',
      },
    });
  });

  Future<void> pumpSelector(WidgetTester tester, {List<String> shelves = const []}) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _Host(initial: shelves)),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the genre suggestions without creating a single shelf', (
    tester,
  ) async {
    await pumpSelector(tester);

    expect(find.text('Crime & thriller'), findsOneWidget);
    expect(find.text('Refine (optional)'), findsNothing);
    expect(repo.created, isEmpty);
  });

  testWidgets('picking a genre files the book and reveals its subgenres', (
    tester,
  ) async {
    await pumpSelector(tester);

    await tester.tap(find.text('Crime & thriller'));
    await tester.pumpAndSettle();

    expect(repo.created, ['Genre', 'Crime & thriller']);

    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.shelves, ['Crime & thriller']);

    // The second level only exists once the parent is picked.
    expect(find.text('Refine (optional)'), findsOneWidget);
    expect(find.text('Thriller'), findsOneWidget);
  });

  testWidgets('picking a subgenre files it under its genre', (tester) async {
    await pumpSelector(tester);

    await tester.tap(find.text('Crime & thriller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thriller'));
    await tester.pumpAndSettle();

    expect(repo.created, ['Genre', 'Crime & thriller', 'Thriller']);

    final thriller = repo.tags.firstWhere((t) => t.name == 'Thriller');
    final crime = repo.tags.firstWhere((t) => t.name == 'Crime & thriller');
    expect(thriller.parentId, crime.id);
  });

  testWidgets('unselecting a genre drops it and its subgenres from the book', (
    tester,
  ) async {
    await pumpSelector(tester, shelves: ['Crime & thriller', 'Thriller']);

    await tester.tap(find.text('Crime & thriller'));
    await tester.pumpAndSettle();

    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.shelves, isEmpty);
    expect(repo.created, isEmpty, reason: 'unselecting never creates a shelf');
  });

  testWidgets('leaves the user own shelves untouched', (tester) async {
    await pumpSelector(tester, shelves: ['À relire cet été']);

    await tester.tap(find.text('Crime & thriller'));
    await tester.pumpAndSettle();

    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.shelves, ['À relire cet été', 'Crime & thriller']);
  });
}
