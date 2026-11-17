import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/cover_grid_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Column counts of the covers grid per cover size: every size keeps a count
// of its own, one column apart; on a phone, from six covers per row down to
// two; elsewhere the default size keeps Flutter's max-extent rule.
void main() {
  final steps = ThemeProvider.homeCoverExtentSteps;
  List<int> columns(double width, {bool phone = false}) => [
    for (final s in steps) coverGridColumns(width, s, phone: phone),
  ];

  // Grid width = screen width minus the 16 px padding on each side.
  const phoneScreens = [320.0, 360, 375, 390, 393, 412, 428, 430, 599];

  test('five sizes, the default among them', () {
    expect(steps, hasLength(5));
    expect(steps, contains(ThemeProvider.homeCoverExtentDefault));
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]));
    }
  });

  test('the three former sizes are still steps', () {
    // A size saved before the slider must keep its place on it.
    expect(steps, containsAll(<double>[110, 150, 200]));
  });

  test('off a phone, the default size keeps the max-extent rule', () {
    // ceil(768 / 166) = 5, as SliverGridDelegateWithMaxCrossAxisExtent.
    expect(coverGridColumns(768, 150), 5);
    expect(coverGridColumns(1200, 150), 8);
  });

  test('on a phone: six, five, four, three, two covers per row', () {
    for (final screen in [320.0, 360, 375, 393, 430]) {
      expect(columns(screen - 32, phone: true), [
        6,
        5,
        4,
        3,
        2,
      ], reason: 'screen $screen');
    }
  });

  test('on every phone width, one column apart from size to size', () {
    for (final screen in phoneScreens) {
      final counts = columns(screen - 32, phone: true);
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], counts[i - 1] - 1, reason: 'screen $screen');
      }
      expect(counts.last, greaterThanOrEqualTo(2), reason: 'screen $screen');
    }
  });

  test('a window past the phone breakpoint keeps one column per step', () {
    // 640 dp window with a navigation rail: the grid is narrower than a
    // phone's widest, but the screen is not a phone.
    expect(columns(520), [7, 6, 5, 4, 3]);
  });

  test('on a tablet, one column per step around the default size', () {
    expect(columns(768), [8, 7, 6, 5, 4]);
  });

  test('sizes stay ordered and distinct from 0 to 2000 px', () {
    for (var w = 0.0; w <= 2000; w += 7) {
      for (final phone in [false, true]) {
        final c = columns(w, phone: phone);
        for (var i = 1; i < c.length - 1; i++) {
          expect(c[i - 1], greaterThan(c[i]), reason: 'width $w');
        }
        expect(c.last, lessThanOrEqualTo(c[c.length - 2]));
        expect(c.last, greaterThanOrEqualTo(1), reason: 'width $w');
      }
    }
  });

  test('the two smallest sizes have tighter gaps', () {
    expect(coverGridCrossSpacing(steps[0]), 8);
    expect(coverGridCrossSpacing(steps[1]), 8);
    for (final s in steps.skip(2)) {
      expect(coverGridCrossSpacing(s), 16);
    }
  });

  test('a size outside the steps follows the plain rule', () {
    expect(coverGridColumns(343, 125), 3);
  });

  testWidgets('the phone test reads the screen, not the grid', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <bool>[];
    Widget probe() => MaterialApp(
      home: Builder(
        builder: (context) {
          seen.add(coverGridIsPhone(context));
          return const SizedBox();
        },
      ),
    );

    tester.view.physicalSize = const Size(599, 800);
    await tester.pumpWidget(probe());
    tester.view.physicalSize = const Size(640, 800);
    await tester.pumpWidget(probe());

    expect(seen.first, isTrue);
    expect(seen.last, isFalse);
  });

  testWidgets('the library grid width leaves out the rail and the padding', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <double>[];
    Widget probe() => MaterialApp(
      home: Builder(
        builder: (context) {
          seen.add(coverGridWidthOf(context));
          return const SizedBox();
        },
      ),
    );

    tester.view.physicalSize = const Size(375, 800);
    await tester.pumpWidget(probe());
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpWidget(probe());

    expect(seen.first, 375 - 32);
    expect(seen.last, 1000 - 89 - 32);
  });
}
