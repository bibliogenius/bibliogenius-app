import 'package:bibliogenius/widgets/app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flutter turns `persist` on as soon as a `SnackBarAction` is present
/// (`snack_bar.dart:303`), which makes `duration` inert. The bar then waits for
/// a tap or a swipe, and because the ScaffoldMessenger lives above the
/// Navigator it follows the reader from screen to screen and holds up every
/// message queued behind it. The import summary offers an action AND has to
/// expire, so it says so.
void main() {
  Widget harness(void Function(BuildContext) show) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => show(context),
          child: const Text('go'),
        ),
      ),
    ),
  );

  testWidgets('an action pins the bar unless the caller opts out', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        (context) => AppSnackBar.error(
          context,
          'pinned',
          action: SnackBarAction(label: 'act', onPressed: () {}),
          duration: const Duration(seconds: 2),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('pinned'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(
      find.text('pinned'),
      findsOneWidget,
      reason: 'this is the Flutter default the import summary must not take',
    );
  });

  testWidgets('persist false lets the duration do its work', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => AppSnackBar.error(
          context,
          'expires',
          action: SnackBarAction(label: 'act', onPressed: () {}),
          persist: false,
          duration: const Duration(seconds: 2),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('expires'), findsOneWidget);

    // Two steps: the dismissal timer is armed once the entrance animation has
    // finished, so the clock has to pass that point first.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('expires'), findsNothing);
  });
}
