import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/shelf_placement_tree.dart';
import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _tags = [
  Tag(id: 'salon', name: 'Salon', count: 0),
  Tag(id: 'romans', name: 'Romans', parentId: 'salon', count: 0),
  Tag(id: 'polar', name: 'Polar', parentId: 'romans', count: 0),
  Tag(id: 'bureau', name: 'Bureau', count: 0),
];

Future<List<Tag?>> _pump(
  WidgetTester tester, {
  List<Tag>? tags,
  String? disabledBranchRootId,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final placed = <Tag?>[];
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: ThemeProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: ShelfPlacementTree(
            allTags: tags ?? _tags,
            title: 'Move “Salon” to…',
            firstLevelLabel: 'At the first level',
            disabledBranchRootId: disabledBranchRootId,
            onPlace: placed.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return placed;
}

Finder _row(String name) => find.byKey(ValueKey('placementRow:$name'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {'filter_shelves_hint': 'Filter shelves'},
    });
  });

  testWidgets('every shelf is listed, unfolded, parents before children', (
    tester,
  ) async {
    await _pump(tester);
    final order = [
      'Bureau',
      'Salon',
      'Romans',
      'Polar',
    ].map((n) => tester.getTopLeft(_row(n)).dy).toList();
    expect(order, orderedEquals([...order]..sort()));
    // Each level sits further right than its parent.
    expect(
      tester.getTopLeft(find.text('Polar')).dx,
      greaterThan(tester.getTopLeft(find.text('Romans')).dx),
    );
  });

  testWidgets('a child name starts right of its parent name, even under '
      'the first-level icon', (tester) async {
    await _pump(tester);
    final salon = tester.getTopLeft(find.text('Salon')).dx;
    final romans = tester.getTopLeft(find.text('Romans')).dx;
    final polar = tester.getTopLeft(find.text('Polar')).dx;
    expect(romans, greaterThan(salon));
    expect(polar, greaterThan(romans));
  });

  testWidgets('a checked sub-shelf is tinted after its guide line, a '
      'first-level one from the edge', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ShelfTreeRow(
                  key: const ValueKey('top'),
                  name: 'Salon',
                  checked: true,
                  onTap: () {},
                ),
                ShelfTreeRow(
                  key: const ValueKey('child'),
                  name: 'Romans',
                  depth: 1,
                  checked: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Rect tint(String key) => tester.getRect(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byWidgetPredicate(
          (w) => w is Ink && w.decoration != null,
        ),
      ),
    );
    expect(tint('top').left, 0, reason: 'first level: the whole row');
    // The parent's guide line stays outside the tint of its children.
    expect(tint('child').left, greaterThan(20));
    expect(
      tint('child').left,
      lessThan(tester.getTopLeft(find.text('Romans')).dx),
    );
  });

  testWidgets('a tap on a row places there', (tester) async {
    final placed = await _pump(tester);
    await tester.tap(_row('Bureau'));
    await tester.pumpAndSettle();
    expect(placed.map((t) => t?.id), ['bureau']);
  });

  testWidgets('the first-level link places with no parent', (tester) async {
    final placed = await _pump(tester);
    await tester.tap(find.text('At the first level'));
    await tester.pumpAndSettle();
    expect(placed, [null]);
  });

  testWidgets('a disabled branch shows but cannot be tapped', (tester) async {
    final handle = tester.ensureSemantics();
    final placed = await _pump(tester, disabledBranchRootId: 'salon');

    for (final name in ['Salon', 'Romans', 'Polar']) {
      expect(_row(name), findsOneWidget);
      await tester.tap(_row(name), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_row(name)),
        containsSemantics(isButton: true, hasEnabledState: true),
      );
      expect(
        tester.getSemantics(_row(name)),
        isNot(containsSemantics(isEnabled: true)),
      );
    }
    expect(placed, isEmpty);

    await tester.tap(_row('Bureau'));
    await tester.pumpAndSettle();
    expect(placed.map((t) => t?.id), ['bureau']);
    handle.dispose();
  });

  testWidgets('the filter narrows the tree, case and accents ignored', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Filter shelves'),
      'BÚREAU',
    );
    await tester.pumpAndSettle();
    expect(_row('Bureau'), findsOneWidget);
    expect(_row('Salon'), findsNothing);
    expect(_row('Polar'), findsNothing);
  });

  // Sync can leave a cycle (two devices moving shelves concurrently) or a
  // shelf whose parent row is gone. Neither may drop out of the tree: no
  // root reaches them, so both are listed at the first level.
  testWidgets('a cycle and an orphan merged from sync show at the first '
      'level', (tester) async {
    await _pump(
      tester,
      tags: [
        Tag(id: 'a', name: 'Alpha', parentId: 'b', count: 0),
        Tag(id: 'b', name: 'Beta', parentId: 'a', count: 0),
        Tag(id: 'o', name: 'Orphan', parentId: 'gone', count: 0),
        Tag(id: 'z', name: 'Zeta', count: 0),
      ],
    );
    final names = ['Alpha', 'Beta', 'Orphan', 'Zeta'];
    for (final name in names) {
      expect(_row(name), findsOneWidget, reason: name);
    }
    // One level: every name starts at the same indent, in shelf order.
    final starts = names.map((n) => tester.getTopLeft(find.text(n))).toList();
    expect(starts.map((o) => o.dx).toSet(), hasLength(1));
    final tops = starts.map((o) => o.dy).toList();
    expect(tops, List.of(tops)..sort());
  });
}
