import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/cover_grid_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Column counts of the covers grid per cover size: every size keeps a count
// of its own; on a phone, six small, at least three medium (so that large
// can keep two), elsewhere the medium size keeps Flutter's max-extent rule.
void main() {
  final steps = ThemeProvider.homeCoverExtentSteps;
  List<int> columns(double width, {bool phone = false}) => [
    for (final s in steps) coverGridColumns(width, s, phone: phone),
  ];

  // Grid width = screen width minus the 16 px padding on each side.
  const phoneScreens = [320.0, 360, 375, 390, 393, 412, 428, 430, 599];

  test('off a phone, medium keeps the max-extent rule', () {
    // ceil(768 / 166) = 5, as SliverGridDelegateWithMaxCrossAxisExtent.
    expect(coverGridColumns(768, 150), 5);
    expect(coverGridColumns(1200, 150), 8);
  });

  test('on a phone: six small, three medium, two large', () {
    for (final screen in [320.0, 360, 375, 393, 430]) {
      expect(columns(screen - 32, phone: true), [
        6,
        3,
        2,
      ], reason: 'screen $screen');
    }
  });

  test('each size has its own column count on every phone width', () {
    for (final screen in phoneScreens) {
      final counts = columns(screen - 32, phone: true);
      expect(counts[0], greaterThan(counts[1]), reason: 'screen $screen');
      expect(counts[1], greaterThan(counts[2]), reason: 'screen $screen');
      expect(counts[2], greaterThanOrEqualTo(2), reason: 'screen $screen');
    }
  });

  test('a window past the phone breakpoint follows the plain rule', () {
    // 640 dp window with a navigation rail: the grid is narrower than a
    // phone's widest, but the screen is not a phone.
    expect(columns(520), [5, 4, 3]);
  });

  test('on a tablet small follows the plain rule, one column above medium', () {
    // 800 px portrait tablet: ceil(768 / (110 + 8)) = 7.
    expect(columns(768), [7, 5, 4]);
  });

  test('sizes stay ordered and distinct from 0 to 2000 px', () {
    for (var w = 0.0; w <= 2000; w += 7) {
      for (final phone in [false, true]) {
        final c = columns(w, phone: phone);
        expect(c[0], greaterThan(c[1]), reason: 'width $w phone $phone');
        expect(c[1], greaterThanOrEqualTo(c[2]), reason: 'width $w');
        expect(c[2], greaterThanOrEqualTo(1), reason: 'width $w');
      }
    }
  });

  test('a size outside the steps follows the plain rule', () {
    expect(coverGridColumns(343, 120), 3);
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
}
