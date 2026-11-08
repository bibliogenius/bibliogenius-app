import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../providers/theme_provider.dart';

/// Columns of the smallest cover size on a phone.
const int coverGridPhoneSmallColumns = 6;

/// Widest grid still laid out as a phone: a screen under 600 px (the
/// app's mobile breakpoint) minus the grid's 16 px padding on each side.
const double coverGridPhoneMaxWidth = 568;

/// Space between covers: tighter at the smallest size, where six covers
/// share a phone row and 16 px gaps would eat a quarter of it.
double coverGridSpacing(
  double extent, {
  List<double> steps = ThemeProvider.homeCoverExtentSteps,
}) => extent == steps.first ? 8 : 16;

/// Number of columns of a covers grid [width] wide whose covers are at most
/// [extent] wide (the home page cover size, see
/// [ThemeProvider.homeCoverExtentSteps]).
///
/// Each size alone would follow Flutter's max-extent rule,
/// `ceil(width / (extent + spacing))`. On a phone that rule gives two
/// neighbouring sizes the same count: a 343 px grid (375 pt iPhone) fits 3
/// columns at 110 px as at 150 px, so "small" looked exactly like
/// "medium". The middle size keeps that rule; every smaller size gets at
/// least one column more than the next one up, every larger size at least
/// one less than the next one down, down to a single column. On a phone the
/// smallest size shows [coverGridPhoneSmallColumns] covers per row.
int coverGridColumns(
  double width,
  double extent, {
  List<double> steps = ThemeProvider.homeCoverExtentSteps,
}) {
  int raw(double e) =>
      math.max(1, (width / (e + coverGridSpacing(e, steps: steps))).ceil());

  final index = steps.indexOf(extent);
  if (index < 0) return raw(extent);

  final anchor = steps.length ~/ 2;
  var count = raw(steps[anchor]);
  if (index < anchor) {
    for (var i = anchor - 1; i >= index; i--) {
      count = math.max(raw(steps[i]), count + 1);
    }
    if (index == 0 && width < coverGridPhoneMaxWidth) {
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
/// [coverGridColumns], gaps from [coverGridSpacing], tiles sharing the width
/// the gaps leave, so each cover size keeps a column count of its own at
/// every width.
class CoverGridDelegate extends SliverGridDelegate {
  const CoverGridDelegate({
    required this.maxCoverExtent,
    required this.childAspectRatio,
  });

  final double maxCoverExtent;
  final double childAspectRatio;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final spacing = coverGridSpacing(maxCoverExtent);
    final count = coverGridColumns(constraints.crossAxisExtent, maxCoverExtent);
    final usable = math.max(
      0.0,
      constraints.crossAxisExtent - spacing * (count - 1),
    );
    final childCrossAxisExtent = usable / count;
    final childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
    return SliverGridRegularTileLayout(
      crossAxisCount: count,
      mainAxisStride: childMainAxisExtent + spacing,
      crossAxisStride: childCrossAxisExtent + spacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CoverGridDelegate oldDelegate) =>
      oldDelegate.maxCoverExtent != maxCoverExtent ||
      oldDelegate.childAspectRatio != childAspectRatio;
}
