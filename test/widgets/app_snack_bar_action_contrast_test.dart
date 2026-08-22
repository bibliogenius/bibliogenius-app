import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/widgets/app_snack_bar.dart';

/// A SnackBarAction takes its colour from the Material theme unless told
/// otherwise, which is `primary`: blue, on the blue `primaryContainer` of a
/// success bar. The message text has always computed a foreground against
/// the bar's own background; the action was the one part that did not, so
/// every action label in the app sat at a poor contrast.
Future<SnackBarAction> _actionFrom(
  WidgetTester tester,
  void Function(BuildContext) show,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => show(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  return tester.widget<SnackBar>(find.byType(SnackBar)).action!;
}

void main() {
  testWidgets('a success action is coloured against the success background', (
    tester,
  ) async {
    final action = await _actionFrom(
      tester,
      (context) => AppSnackBar.success(
        context,
        'Saved',
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );

    final scheme = ThemeData().colorScheme;
    expect(action.textColor, scheme.onPrimaryContainer);
    expect(action.label, 'Undo');
  });

  testWidgets('an info action is coloured against the info background', (
    tester,
  ) async {
    final action = await _actionFrom(
      tester,
      (context) => AppSnackBar.info(
        context,
        'Hidden',
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );

    expect(action.textColor, ThemeData().colorScheme.onSecondaryContainer);
  });

  testWidgets('the action still fires the caller callback', (tester) async {
    var tapped = false;
    final action = await _actionFrom(
      tester,
      (context) => AppSnackBar.success(
        context,
        'Saved',
        action: SnackBarAction(label: 'Undo', onPressed: () => tapped = true),
      ),
    );

    action.onPressed();
    expect(tapped, isTrue, reason: 'recolouring must not swallow the action');
  });
}
