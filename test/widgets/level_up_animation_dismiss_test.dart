import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/level_up_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The level-up overlay sits above the whole app and swallows every tap. It
/// used to remove itself from the `forward()` future only; a tap-to-dismiss
/// interrupted that future (Flutter cancels it, it never resolves) and parked
/// the timeline at the start of the fade-out, so the overlay stayed on screen
/// until the app was killed.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {'level_up': 'Level up!', 'level': 'Level'},
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => LevelUpAnimation.show(
                  context,
                  newLevel: 1,
                  trackName: 'Collector',
                  trackColor: Colors.green,
                  levelLabel: 'Novice',
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('runs to the end and removes itself', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Novice'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Novice'), findsNothing);
  });

  testWidgets('a tap during the celebration still removes it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Novice'), findsOneWidget);

    await tester.tap(find.text('Novice'), warnIfMissed: false);
    await tester.pump();
    // Long enough for the short jump plus the fade-out, well short of the
    // full timeline so the test proves the tap path, not the natural end.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Novice'), findsNothing);
  });

  testWidgets('a second tap while jumping does not strand it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    await tester.tap(find.text('Novice'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Novice'), warnIfMissed: false);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Novice'), findsNothing);
  });
}
