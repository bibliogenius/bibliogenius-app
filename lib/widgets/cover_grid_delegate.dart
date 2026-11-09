import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../providers/theme_provider.dart';

/// Columns of the smallest cover size on a phone.
const int coverGridPhoneSmallColumns = 6;

/// Fewest columns of the middle cover size on a phone: three, so that the
/// largest size can still show two covers side by side.
const int coverGridPhoneMediumColumns = 3;

/// Whether the screen is laid out as a phone: under the app's 600 px mobile
/// breakpoint, below which there is no navigation rail. Read from the
/// screen, not from the grid, which a rail would narrow on a wider window.
bool coverGridIsPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

/// Horizontal gap between covers: tighter at the smallest size, where six
/// covers share a phone row and 16 px gaps would eat a quarter of it. The
/// vertical gap stays 16 px at every size: the favorite ribbon overhangs a
/// cover's top edge by about 15 px and must not reach the cover above.
double coverGridCrossSpacing(
  double step, {
  List<double> steps = ThemeProvider.homeCoverExtentSteps,
}) => step == steps.first ? 8 : 16;

const double _mainAxisSpacing = 16;

/// Number of columns of a covers grid [width] wide at the cover size
/// [step], one of [ThemeProvider.homeCoverExtentSteps].
///
/// The steps were first read as maximum cover widths with Flutter's rule,
/// `ceil(width / (step + spacing))`. On a phone that rule gives two
/// neighbouring sizes the same count: a 343 px grid (375 pt iPhone) fits 3
/// columns at 110 as at 150. The count now comes from the middle size:
/// - the middle size keeps that rule, with at least
///   [coverGridPhoneMediumColumns] columns on a phone;
/// - every smaller size has at least one column more than the next one up,
///   and the smallest one [coverGridPhoneSmallColumns] on a phone;
/// - every larger size has at least one column less than the next one down,
///   never below one.
///
/// A value outside the steps follows the plain rule.
int coverGridColumns(
  double width,
  double step, {
  bool phone = false,
  List<double> steps = ThemeProvider.homeCoverExtentSteps,
}) {
  int raw(double s) => math.max(
    1,
    (width / (s + coverGridCrossSpacing(s, steps: steps))).ceil(),
  );

  final index = steps.indexOf(step);
  if (index < 0) return raw(step);

  final anchor = steps.length ~/ 2;
  var count = raw(steps[anchor]);
  if (phone) count = math.max(count, coverGridPhoneMediumColumns);
  if (index < anchor) {
    for (var i = anchor - 1; i >= index; i--) {
      count = math.max(raw(steps[i]), count + 1);
    }
    if (index == 0 && phone) {
      count = math.max(count, coverGridPhoneSmallColumns);
    }
  } else {
    for (var i = anchor + 1; i <= index; i++) {
      count = math.max(1, math.min(raw(steps[i]), count - 1));
    }
  }
  return count;
}

/// Grid delegate of the library covers grids: columns from
/// [coverGridColumns], gaps from [coverGridCrossSpacing], tiles sharing the
/// width the gaps leave, so each cover size keeps a column count of its own
/// at every width.
class CoverGridDelegate extends SliverGridDelegate {
  const CoverGridDelegate({
    required this.coverSize,
    required this.childAspectRatio,
    required this.phone,
  });

  /// The cover size step (see [coverGridColumns]).
  final double coverSize;
  final double childAspectRatio;

  /// Whether the screen is a phone (see [coverGridIsPhone]).
  final bool phone;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final spacing = coverGridCrossSpacing(coverSize);
    final count = coverGridColumns(
      constraints.crossAxisExtent,
      coverSize,
      phone: phone,
    );
    final usable = math.max(
      0.0,
      constraints.crossAxisExtent - spacing * (count - 1),
    );
    final childCrossAxisExtent = usable / count;
    final childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
    return SliverGridRegularTileLayout(
      crossAxisCount: count,
      mainAxisStride: childMainAxisExtent + _mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + spacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CoverGridDelegate oldDelegate) =>
      oldDelegate.coverSize != coverSize ||
      oldDelegate.childAspectRatio != childAspectRatio ||
      oldDelegate.phone != phone;
}
