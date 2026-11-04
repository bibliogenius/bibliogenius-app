import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The second line's control is 44 pt tall, so it reaches beside the name:
/// the row has to say who a tap in that overlap belongs to.
void main() {
  testWidgets('the name wins the overlap, the rest of the action stays the '
      "action's", (tester) async {
    var opened = 0;
    var folded = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: ShelfTreeRow(
                name: 'A long shelf name',
                subtitle: 'x',
                onTap: () => opened++,
                subtitleAction: GestureDetector(
                  key: const Key('action'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => folded++,
                  child: const SizedBox(width: 300, height: 44),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final action = tester.getRect(find.byKey(const Key('action')));
    final name = tester.getRect(find.text('A long shelf name'));
    final overlap = action.intersect(name);
    expect(overlap.isEmpty, isFalse, reason: 'the fixture has to overlap');

    await tester.tapAt(overlap.center);
    await tester.pump();
    expect((opened, folded), (1, 0));

    await tester.tapAt(Offset(action.center.dx, action.bottom - 4));
    await tester.pump();
    expect((opened, folded), (1, 1));

    // Beside a name that ends early, the whole 44 pt are the action's.
    await tester.tapAt(Offset(action.right - 2, action.top + 2));
    await tester.pump();
    expect((opened, folded), (1, 2));
  });

  testWidgets('without an action the row keeps its plain two lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShelfTreeRow(name: 'Novels', subtitle: '3 books'),
        ),
      ),
    );

    expect(find.text('3 books'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });
}
