import 'package:bibliogenius/widgets/goal_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 180, child: child)),
  ),
);

void main() {
  testWidgets('a plain tile shows no dismiss affordance', (tester) async {
    await tester.pumpWidget(
      _host(GoalTile(icon: Icons.public, label: 'Go public', onTap: () {})),
    );

    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('a dismissible tile reports its own dismissal', (tester) async {
    var dismissed = 0;
    var tapped = 0;

    await tester.pumpWidget(
      _host(
        GoalTile(
          icon: Icons.public,
          label: 'Go public',
          onTap: () => tapped++,
          onDismiss: () => dismissed++,
          dismissTooltip: 'Hide this suggestion',
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissed, 1);
    expect(
      tapped,
      0,
      reason: 'dismissing must not also trigger the tile navigation',
    );
  });

  testWidgets('the dismiss affordance is labelled for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GoalTile(
          icon: Icons.public,
          label: 'Go public',
          onTap: () {},
          onDismiss: () {},
          dismissTooltip: 'Hide this suggestion',
        ),
      ),
    );

    expect(find.byTooltip('Hide this suggestion'), findsOneWidget);
  });
}
