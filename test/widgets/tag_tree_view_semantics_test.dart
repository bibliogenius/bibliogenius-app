// Accessibility cover for the shelf tree's expand/collapse chevron.
//
// The chevron was a bare `GestureDetector` around an `Icon`: no name, no role,
// and no way to tell a collapsed branch from an expanded one by ear. The state
// rides on `Semantics(expanded:)` rather than a translated label on purpose,
// so the platform speaks "expanded" or "collapsed" in the reader's own
// language and no catalogue key has to carry it.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/widgets/tag_tree_view.dart';

/// The view rebuilds the hierarchy from `parentId` and ignores any
/// [Tag.children] passed in, so the fixture has to be flat to grow a branch.
List<Tag> _tree() => [
  Tag(id: 'parent', name: 'Fiction', count: 3),
  Tag(id: 'child', name: 'Science fiction', parentId: 'parent', count: 1),
];

Future<void> _pumpTags(WidgetTester tester, List<Tag> tags) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TagTreeView(
          tags: tags,
          selectedTagIds: const {},
          onTagSelected: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The chevron's own semantics node.
///
/// Reached through the icon rather than the label: the row above also
/// announces the shelf name, and a label lookup lands on it instead.
SemanticsNode _chevron(WidgetTester tester) =>
    tester.getSemantics(find.byIcon(Icons.keyboard_arrow_right));

void main() {
  testWidgets('the chevron announces the shelf it opens, as a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpTags(tester, _tree());

    final node = _chevron(tester);
    expect(node.label, 'Fiction');
    expect(node.flagsCollection.isButton, isTrue);

    handle.dispose();
  });

  testWidgets('the collapsed and expanded states are distinguishable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpTags(tester, _tree());

    // `null` here means the node carries no expanded state at all, which is
    // how a reader loses the collapsed/expanded distinction entirely.
    expect(
      _chevron(tester).flagsCollection.isExpanded.toBoolOrNull(),
      isFalse,
      reason: 'a branch starts collapsed, and must say so',
    );

    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pumpAndSettle();

    expect(
      _chevron(tester).flagsCollection.isExpanded.toBoolOrNull(),
      isTrue,
      reason: 'opening the branch must be audible, not just visible',
    );
    expect(find.text('Science fiction'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('a leaf shelf exposes no chevron to tab through', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpTags(tester, [Tag(id: 'leaf', name: 'Essays', count: 2)]);

    expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);

    handle.dispose();
  });
}
