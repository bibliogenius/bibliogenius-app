import 'dart:math' as math;

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/loan_return_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backend deletes the borrowed copy whether or not it reached the lender.
/// When it did not, the book stays out on loan on the lender's side and only the
/// user can close it: the return must not read as a success.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'book_returned_success': 'Book returned successfully',
        'book_returned_lender_not_notified':
            'Book removed, but the lender could not be notified.',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  /// Builds the SnackBar inside a real element tree: `translate` reads the
  /// ThemeProvider off the context.
  Future<SnackBar> build(WidgetTester tester, {required bool notified}) async {
    late SnackBar bar;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              bar = returnOutcomeSnackBar(context, notified);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return bar;
  }

  testWidgets('a notified return confirms success', (tester) async {
    final bar = await build(tester, notified: true);
    expect((bar.content as Text).data, 'Book returned successfully');
  });

  testWidgets('a silent return warns instead of confirming', (tester) async {
    final bar = await build(tester, notified: false);
    final text = (bar.content as Text).data!;
    expect(text, contains('could not be notified'));
    expect(
      text,
      isNot(contains('successfully')),
      reason: 'the lender never heard: this is not a success',
    );
    expect(
      bar.backgroundColor,
      isNot(equals((await build(tester, notified: true)).backgroundColor)),
    );
  });

  // WCAG 2.1 AA, normal text. Material 3 would otherwise draw the content in
  // `colorScheme.onInverseSurface`, which flips with the theme and lands dark on
  // our fixed backgrounds. Both ends are pinned, so compute the ratio and check
  // it rather than trust the constants.
  group('contrast', () {
    /// WCAG relative luminance of an opaque colour.
    double luminance(Color c) {
      double channel(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4) as double;
      return 0.2126 * channel(c.r) +
          0.7152 * channel(c.g) +
          0.0722 * channel(c.b);
    }

    double ratio(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      final (hi, lo) = la > lb ? (la, lb) : (lb, la);
      return (hi + 0.05) / (lo + 0.05);
    }

    testWidgets('both pills clear AA against their text', (tester) async {
      for (final notified in [true, false]) {
        final bar = await build(tester, notified: notified);
        final foreground = (bar.content as Text).style!.color!;
        final background = bar.backgroundColor!;
        expect(
          ratio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'notified=$notified: WCAG 2.1 AA needs 4.5:1 for normal text',
        );
      }
    });

    testWidgets('the text colour is pinned, not inherited from the theme', (
      tester,
    ) async {
      final bar = await build(tester, notified: false);
      expect(
        (bar.content as Text).style?.color,
        isNotNull,
        reason: 'an inherited colour flips with the theme and breaks contrast',
      );
    });
  });

  testWidgets('the warning lingers, because it asks the user to act', (
    tester,
  ) async {
    final silent = await build(tester, notified: false);
    final ok = await build(tester, notified: true);
    expect(silent.duration, greaterThan(ok.duration));
  });
}
