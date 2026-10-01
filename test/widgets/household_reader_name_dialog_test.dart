import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/household_reader_name_dialog.dart';

/// The reader name dialog owns a TextEditingController that must outlive the
/// dialog's closing transition: `showDialog` resolves on pop, while the
/// TextField is still on screen for the whole fade-out. Disposing the
/// controller right away raised "A TextEditingController was used after being
/// disposed" on the next rebuild.
void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({
      'en': {
        'household_add_reader': 'Add a reader',
        'household_name': 'First name',
        'household_confirm': 'Create',
        'cancel': 'Cancel',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    late BuildContext screenContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                screenContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return screenContext;
  }

  testWidgets('confirming the name survives the closing transition', (
    tester,
  ) async {
    final screenContext = await pumpHost(tester);

    final result = showHouseholdReaderNameDialog(
      screenContext,
      titleKey: 'household_add_reader',
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Claire ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    // Runs the pop transition frame by frame: this is where the disposed
    // controller used to be rebuilt.
    await tester.pumpAndSettle();

    expect(await result, 'Claire');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the name field is capped at the backend limit', (tester) async {
    final screenContext = await pumpHost(tester);

    final result = showHouseholdReaderNameDialog(
      screenContext,
      titleKey: 'household_add_reader',
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'a' * (maxReaderNameLength + 10),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(await result, 'a' * maxReaderNameLength);
  });
}
