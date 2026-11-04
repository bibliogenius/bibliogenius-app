import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The second line's control is 44 pt tall, so it reaches beside the name:
/// the row has to say who a tap in that overlap belongs to.
double width = 400;

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

  group('the two lines never overlap', () {
    const action = Text('2 sub-shelves', key: Key('button'));
    Widget row({String? notice, double scale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ShelfTreeRow(
                key: const Key('row'),
                name: 'Novels',
                subtitle: '10 books',
                subtitleNotice: notice,
                subtitleAction: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: action,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final (w, wraps) in [(800.0, false), (180.0, true)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$w wide at text scale $scale', (tester) async {
          width = w;
          await tester.pumpWidget(row(scale: scale));

          final name = tester.getRect(find.text('Novels'));
          final count = tester.getRect(find.text('10 books'));
          final button = tester.getRect(find.byKey(const Key('button')));
          expect(name.bottom, lessThanOrEqualTo(count.top), reason: 'name');
          if (wraps) {
            // The count wrapped apart from the button's text, right below.
            expect(count.bottom, lessThanOrEqualTo(button.top));
            // Only the button's own padding between them, not a whole run.
            expect(button.top - count.bottom, closeTo(14, 1));
            expect(count.left, button.left);
          } else {
            expect(button.center.dy, closeTo(count.center.dy, 1));
            expect(button.left, greaterThan(count.right));
          }
        });
      }
    }

    testWidgets('a notice keeps the height of the row and hides the rest', (
      tester,
    ) async {
      for (final w in [800.0, 180.0]) {
        width = w;
        await tester.pumpWidget(row());
        final height = tester.getSize(find.byKey(const Key('row'))).height;

        await tester.pumpWidget(row(notice: 'Drop into Novels'));

        expect(tester.getSize(find.byKey(const Key('row'))).height, height);
        expect(find.text('Drop into Novels'), findsOneWidget);
        expect(
          tester
              .widget<Visibility>(
                find.ancestor(
                  of: find.text('10 books'),
                  matching: find.byType(Visibility),
                ),
              )
              .visible,
          isFalse,
        );
      }
    });
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
