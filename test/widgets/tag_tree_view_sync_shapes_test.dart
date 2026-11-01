// The shelf tree as sync can leave it: a cycle and a shelf whose parent row
// is gone. Both used to drop out of the tree (no root reaches them); they are
// shown at the first level, and building the tree terminates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/widgets/tag_tree_view.dart';

void main() {
  testWidgets('a cycle and an orphan are listed at the first level', (
    tester,
  ) async {
    final tags = [
      Tag(id: 'a', name: 'Alpha', parentId: 'b', count: 0),
      Tag(id: 'b', name: 'Beta', parentId: 'a', count: 0),
      Tag(id: 'o', name: 'Orphan', parentId: 'gone', count: 0),
      Tag(id: 'z', name: 'Zeta', count: 0),
    ];

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

    for (final name in ['Alpha', 'Beta', 'Orphan', 'Zeta']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // First level, in shelf order: no branch chevron, all four side by side.
    expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);
    final tops = ['Alpha', 'Beta', 'Orphan', 'Zeta']
        .map((n) => tester.getTopLeft(find.text(n)).dy)
        .toList();
    expect(tops, List.of(tops)..sort());
  });
}
