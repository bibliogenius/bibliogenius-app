import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/restart_required_dialog.dart';

/// After a full reset the engine still holds the previous identity in memory:
/// the app must be closed before anything else happens, so the dialog cannot
/// be dismissed and its only way out closes the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'reset_full_done_title': 'Reset complete',
        'reset_full_restart_hint': 'Close the app, then reopen it.',
        'wizard_restore_button_close_app': 'Close the app',
      },
    });
  });

  Future<int Function()> open(WidgetTester tester) async {
    var closes = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showRestartRequiredDialog(context, onClose: () => closes++),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return () => closes;
  }

  testWidgets('tells the user to close the app and closes it on tap', (
    tester,
  ) async {
    final closes = await open(tester);

    expect(find.text('Reset complete'), findsOneWidget);
    expect(find.text('Close the app, then reopen it.'), findsOneWidget);

    await tester.tap(find.text('Close the app'));
    await tester.pump();
    expect(closes(), 1);
  });

  testWidgets('cannot be dismissed by the barrier or the back button', (
    tester,
  ) async {
    await open(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Reset complete'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reset complete'), findsOneWidget);
  });
}
