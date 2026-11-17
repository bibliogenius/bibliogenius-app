import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../providers/theme_provider.dart';
import 'scaffold_with_nav.dart';

/// Fewest columns of the default cover size on a phone: three, so that the
/// largest size can still show two covers side by side, and the smallest,
/// one column more per step, six.
const int coverGridPhoneDefaultColumns = 3;

/// Whether the screen is laid out as a phone: no navigation rail, same
/// breakpoint as the shell ([usesNavigationRail]). Read from the screen, not
/// from the grid, which a rail would narrow on a wider window.
bool coverGridIsPhone(BuildContext context) => !usesNavigationRail(context);

/// Tile ratio of the library covers grid (width / height): a standard book.
const double coverGridAspectRatio = 0.65;

/// Padding around the library covers grid, on each side.
const double coverGridPadding = 16;

/// Width of the library covers grid on this screen, as the home page lays
/// it out: the window less the navigation rail, when there is one, and the
/// grid's padding. Lets a screen other than the library (the cover size
/// preview in Settings) draw the grid at its true column count.
double coverGridWidthOf(BuildContext context) {
  final rail = usesNavigationRail(context)
      ? navRailMinWidth + navRailDividerWidth
      : 0.0;
  return math.max(
    1.0,
    MediaQuery.sizeOf(context).width - rail - 2 * coverGridPadding,
  );
}

/// Horizontal gap between covers: tighter at the two smallest sizes, where
/// five or six covers share a phone row and 16 px gaps would eat a quarter
/// of it. The vertical gap stays 16 px at every size: the favorite ribbon
/// overhangs a cover's top edge by about 15 px and must not reach the cover
/// above.
double coverGridCrossSpacing(
  double step, {
  List<double> steps = ThemeProvider.homeCoverExtentSteps,
}) {
  final index = steps.indexOf(step);
  return index == 0 || index == 1 ? 8 : 16;
}

const double _mainAxisSpacing = 16;

/// Number of columns of a covers grid [width] wide at the cover size
/// [step], one of [ThemeProvider.homeCoverExtentSteps].
///
/// The steps were first read as maximum cover widths with Flutter's rule,
/// `ceil(width / (step + spacing))`. On a phone that rule gives neighbouring
/// sizes the same count: a 343 px grid (375 pt iPhone) fits 3 columns at 110
/// as at 150. The count now comes from the default size
/// ([ThemeProvider.homeCoverExtentDefault]):
/// - the default size keeps that rule, with at least
///   [coverGridPhoneDefaultColumns] columns on a phone;
/// - every smaller size has at least one column more than the next one up;
/// - every larger size has at least one column less than the next one down,
///   never below one.
///
/// On a phone this gives one column per step, six covers per row down to
/// two. A value outside the steps follows the plain rule.
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

  final defaultIndex = steps.indexOf(ThemeProvider.homeCoverExtentDefault);
  final anchor = defaultIndex < 0 ? steps.length ~/ 2 : defaultIndex;
  var count = raw(steps[anchor]);
  if (phone) count = math.max(count, coverGridPhoneDefaultColumns);
  if (index < anchor) {
    for (var i = anchor - 1; i >= index; i--) {
      count = math.max(raw(steps[i]), count + 1);
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
