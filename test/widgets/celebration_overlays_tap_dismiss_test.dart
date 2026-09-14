import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/achievement_pop_animation.dart';
import 'package:bibliogenius/widgets/badge_unlock_animation.dart';
import 'package:bibliogenius/widgets/book_complete_animation.dart';
import 'package:bibliogenius/widgets/goal_reached_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every celebration overlay covers the app and swallows taps. They all used
/// to remove themselves from the `forward()` future, which Flutter cancels
/// (never resolves) as soon as tap-to-dismiss calls `animateTo`: the tap
/// faded the celebration out but left an invisible full-screen entry eating
/// every touch until the app was killed.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {'achievement_unlocked': 'Unlocked'},
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester, void Function(BuildContext) show) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fires the overlay, taps it mid-flight, then checks it is gone well
  /// before its natural end (so the tap path is what is being proven).
  Future<void> expectTapRemoves(
    WidgetTester tester,
    void Function(BuildContext) show,
    Finder marker,
  ) async {
    await pump(tester, show);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(marker, findsOneWidget);

    await tester.tap(marker, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(marker, findsNothing);
  }

  testWidgets('achievement pop', (tester) async {
    await expectTapRemoves(
      tester,
      (context) => AchievementPopAnimation.show(
        context,
        achievementName: 'Bookworm',
      ),
      find.text('Bookworm'),
    );
  });

  testWidgets('badge unlock', (tester) async {
    await expectTapRemoves(
      tester,
      (context) => BadgeUnlockAnimation.show(
        context,
        badgeName: 'Explorer',
        badgeAssetPath: 'assets/images/badges/curieux.svg',
        badgeColor: Colors.blue,
      ),
      find.text('Explorer'),
    );
  });

  testWidgets('book complete', (tester) async {
    await expectTapRemoves(
      tester,
      (context) => BookCompleteCelebration.show(context, bookTitle: 'Dune'),
      find.text('Dune'),
    );
  });

  testWidgets('goal reached', (tester) async {
    await expectTapRemoves(
      tester,
      (context) => GoalReachedAnimation.show(
        context,
        goalType: 'yearly',
        booksRead: 12,
        customMessage: 'Twelve down',
      ),
      find.text('Twelve down'),
    );
  });
}
