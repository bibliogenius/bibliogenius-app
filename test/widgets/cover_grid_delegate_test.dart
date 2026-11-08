import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/cover_grid_delegate.dart';
import 'package:flutter_test/flutter_test.dart';

// Column counts of the covers grid per cover size: the middle size keeps
// Flutter's max-extent rule, every size keeps a count of its own, and the
// smallest one shows six covers per row on a phone.
void main() {
  final steps = ThemeProvider.homeCoverExtentSteps;
  List<int> columns(double width) => [
    for (final e in steps) coverGridColumns(width, e),
  ];

  test('medium keeps the max-extent rule', () {
    // ceil(768 / 166) = 5, as SliverGridDelegateWithMaxCrossAxisExtent.
    expect(coverGridColumns(768, 150), 5);
    expect(coverGridColumns(328, 150), 2);
  });

  test('each size has its own column count on common phone widths', () {
    // Grid width = screen width minus the 16 px padding on each side.
    for (final screen in [320.0, 360, 375, 390, 393, 412, 428, 430]) {
      final counts = columns(screen - 32);
      expect(counts[0], greaterThan(counts[1]), reason: 'screen $screen');
      expect(counts[1], greaterThan(counts[2]), reason: 'screen $screen');
    }
  });

  test('on a 375 pt phone: 6, 3 and 2 columns', () {
    expect(columns(343), [6, 3, 2]);
  });

  test('small shows six covers per row on every phone width', () {
    for (final screen in [320.0, 360, 375, 390, 393, 412, 428, 430, 599]) {
      expect(columns(screen - 32)[0], 6, reason: 'screen $screen');
    }
  });

  test('on a tablet small follows the plain rule, one column above medium', () {
    // 800 px portrait tablet: ceil(768 / (110 + 8)) = 7.
    expect(columns(768), [7, 5, 4]);
  });

  test('large never goes below one column', () {
    expect(columns(150)[2], 1);
  });

  test('a size outside the steps follows the plain rule', () {
    expect(coverGridColumns(343, 120), 3);
  });
}
