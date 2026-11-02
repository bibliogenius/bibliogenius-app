// Shelf names are unique byte for byte in the database (`tags.name UNIQUE`,
// case- and accent-sensitive), so "Etagere" and "Étagère" can both exist,
// created before the picker refused near-duplicates, imported, or merged
// from sync. Folding case and accents is only for telling a reader that a
// name is taken; what is checked or saved must compare names exactly, or a
// book on one shelf would silently be filed on its look-alike too.

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/hierarchical_tag_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_repositories.dart';

Finder _row(String name) => find.byKey(ValueKey('shelfRow:$name'));

Future<List<List<String>>> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = MockTagRepository()
    ..mockTags = [
      Tag(id: 'plain', name: 'Etagere', count: 1),
      Tag(id: 'accented', name: 'Étagère', count: 0),
    ];
  final changes = <List<String>>[];
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        Provider<TagRepository>.value(value: repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: HierarchicalTagSelector(
            selectedTags: const ['Etagere'],
            onTagsChanged: (tags) => changes.add(List.of(tags)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changes;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'recent_shelf_names': ['Étagère'],
    });
    TranslationService.setPoTranslationsForTest({
      'en': {
        'add_tag': 'Add',
        'done': 'Done',
        'recent_shelves': 'Recent',
        'search_or_create_shelf_hint': 'Search or create a shelf',
        'create_shelf_named': 'Create “{name}”',
      },
    });
  });

  testWidgets('the picker checks only the shelf the book is on', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final changes = await _pump(tester);

    await tester.tap(find.byKey(const Key('addShelfChip')));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_row('Etagere')),
      containsSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(
      tester.getSemantics(_row('Étagère')),
      containsSemantics(hasCheckedState: true, isChecked: false),
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(changes.last, ['Etagere']);
    handle.dispose();
  });

  testWidgets('the look-alike is still offered as recent, and can be added', (
    tester,
  ) async {
    final changes = await _pump(tester);
    final recent = find.byKey(const ValueKey('recentShelf:Étagère'));

    expect(recent, findsOneWidget);
    await tester.tap(recent);
    await tester.pumpAndSettle();
    expect(changes.last, ['Etagere', 'Étagère']);
  });

  testWidgets('a name taken up to case and accents still offers no "Create"', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('addShelfChip')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search or create a shelf'),
      'ETAGERE',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Create'), findsNothing);
  });
}
