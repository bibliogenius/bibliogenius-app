import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'shelf_fan_flight.dart';
import 'shelf_thumbnail.dart';

/// The ground of a shelf surface: that of the theme's cards.
Color shelfSurfaceColor(ThemeData theme) =>
    theme.cardTheme.color ?? theme.cardColor;

/// The outline of a shelf surface: the line of the theme's cards, around the
/// corners the shelves keep whatever the theme.
ShapeBorder shelfSurfaceShape(ThemeData theme, double radius) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: shelfSurfaceSide(theme),
    );

/// The line of the theme's cards.
BorderSide shelfSurfaceSide(ThemeData theme) {
  final themed = theme.cardTheme.shape;
  return themed is OutlinedBorder ? themed.side : BorderSide.none;
}

/// How many columns of shelf cards fit [width]: one on a very narrow screen
/// or with large text, where two would cut the names short.
int shelfGridColumns({required double width, required double textScale}) {
  if (width < 360 || textScale >= 1.3) return 1;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}

/// How many columns of the big cards fit [width]: one more step than
/// [shelfGridColumns], whose two columns would cut a common word of a name of
/// 18 pt in the middle.
int shelfCardGridColumns({required double width, required double textScale}) {
  if (width < 390 && textScale >= 1.2) return 1;
  return shelfGridColumns(width: width, textScale: textScale);
}

/// The counts of a shelf, to print or to announce: its books, whatever their
/// number, then its sub-shelves when it has some.
List<String> shelfCountLabels(
  BuildContext context, {
  required int books,
  required int subShelves,
}) {
  String plural(String key, int count) => TranslationService.translate(
    context,
    count == 1 ? key : '${key}_plural',
  ).replaceAll('%d', '$count');

  return [
    plural('displayed_books_count', books),
    if (subShelves > 0) plural('sub_shelves_count', subShelves),
  ];
}

/// A shelf to walk into: its fan of covers, its name, its counts. One button,
/// named by the shelf and its counts.
///
/// On the grid it is the theme's card, dressed in the colour of its shelf by
/// [_ShelfCardBandDress]. The small form stays on the plain card.
class ShelfCard extends StatelessWidget {
  static const double _padding = 13;
  static const double _nameSize = 18;
  static const double _nameHeight = 1.18;
  static const double _countSize = 13;
  static const double _countHeight = 1.25;
  static const double _nameGap = 3;

  /// The least air between the band and a name on two lines; a shorter name
  /// has more.
  static const double _bandGap = 6;
  static const int _maxLines = 2;

  /// The colour of the card in the palette, from [tintSlotsOf]; the small form
  /// has none.
  final int? tintSlot;
  final String name;
  final int books;
  final int subShelves;
  final List<String> coverPaths;

  /// The small form, for a sub-shelf on a shelf's page.
  final bool compact;
  final VoidCallback onTap;

  /// Sends the fan off on its way to the shelf's page, on a tap.
  final ShelfFanFlight? flight;

  const ShelfCard({
    super.key,
    required int this.tintSlot,
    required this.name,
    required this.books,
    required this.subShelves,
    required this.onTap,
    this.coverPaths = const [],
    this.flight,
  }) : compact = false;

  const ShelfCard.compact({
    super.key,
    required this.name,
    required this.books,
    required this.subShelves,
    required this.onTap,
    this.coverPaths = const [],
    this.flight,
  }) : tintSlot = null,
       compact = true;

  /// The height of a row of [ShelfCard.compact]: two lines of name at most,
  /// and never under the 44 pt of a target.
  static double compactExtentFor(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final text =
        scaler.scale(14) * (theme.bodyMedium?.height ?? 1.4) * _maxLines;
    const tile = 34.0;
    // A rounding margin: text metrics land a fraction above these sums.
    final extent = (text > tile ? text : tile) + 8 * 2 + 2;
    return extent < 44 ? 44 : extent;
  }

  /// The height of a grid row: the band, then two lines of name and one of
  /// count at the text scale in use, so that no card overflows and rows stay
  /// aligned.
  static double extentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Rounded up, a point or two above what the text ends up taking: the rest
    // goes to the air under the band.
    final name = (scaler.scale(_nameSize) * _nameHeight * _maxLines).ceil();
    final count = (scaler.scale(_countSize) * _countHeight).ceil();
    return _ShelfCardBandDress.bandHeight +
        _bandGap +
        name +
        _nameGap +
        count +
        _padding;
  }

  /// The colour slot of every shelf of [tags], by [Tag.stableKey]: sisters
  /// differ, level by level, as far as the palette goes.
  static Map<String, int> tintSlotsOf(List<Tag> tags) => {
    for (final sisters in Tag.childrenIndex(tags).values)
      ...AppDesign.shelfTintSlots(sisters.map((tag) => tag.stableKey)),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = shelfCountLabels(
      context,
      books: books,
      subShelves: subShelves,
    );
    final corner = compact ? 14.0 : 20.0;
    final tint = compact
        ? null
        : AppDesign.shelfTint(tintSlot!, theme.brightness);
    final veils = compact ? null : AppDesign.shelfCardVeils(theme.brightness);

    final fanSize = compact ? ShelfThumbnailSize.s : ShelfThumbnailSize.l;
    // Under a band, the empty fan is drawn for the band and stays there: it has
    // no place on the page of the shelf in that colour.
    final flies = compact || (books > 0 && coverPaths.isNotEmpty);
    late BuildContext fanContext;
    final fan = Builder(
      builder: (context) {
        fanContext = context;
        return ShelfThumbnail(
          size: fanSize,
          hasBooks: books > 0,
          coverPaths: coverPaths,
          ghostColor: tint == null ? null : AppDesign.shelfBandGhostColor,
        );
      },
    );

    final countText = Text(
      // The sub-shelves are in the mark.
      counts.first,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: _countSize,
        height: _countHeight,
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: _maxLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: _nameSize,
            fontWeight: FontWeight.w800,
            height: _nameHeight,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: _nameGap),
        if (subShelves > 0 && tint != null)
          Row(
            children: [
              Expanded(
                // Smaller rather than cut: a count is nothing without its
                // digits.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: countText,
                ),
              ),
              const SizedBox(width: 6),
              _SubShelvesMark(count: subShelves, ink: tint.ink),
            ],
          )
        else
          countText,
      ],
    );

    final ink = InkWell(
      // The theme's overlays are made for its plain surfaces, not for a card
      // that also carries a colour. The keyboard gets a ring, not a veil.
      splashColor: veils?.splash,
      highlightColor: veils?.highlight,
      hoverColor: veils?.hover,
      focusColor: tint == null ? null : Colors.transparent,
      onTap: () {
        if (flies) {
          final box = fanContext.findRenderObject() as RenderBox?;
          if (box != null) {
            flight?.takeOff(
              context,
              name: name,
              from: box.localToGlobal(Offset.zero) & box.size,
              size: fanSize,
              hasBooks: books > 0,
              coverPaths: coverPaths,
            );
          }
        }
        onTap();
      },
      child: ExcludeSemantics(
        child: tint == null
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    fan,
                    const SizedBox(width: 10),
                    Expanded(
                      // Only a bare number at the right: the sentence would
                      // compete with the count of the head. A screen reader
                      // still gets it whole.
                      child: Text(
                        name,
                        maxLines: _maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$books',
                      // The theme's own muted colour: its
                      // onSurfaceVariant can be the name's.
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : _ShelfCardBandDress(
                tint: tint,
                fan: fan,
                text: text,
              ),
      ),
    );

    final line = shelfSurfaceSide(theme).width;

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: [name, ...counts].join(', '),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(corner),
            boxShadow: AppDesign.subtleShadow,
          ),
          child: Material(
            color: shelfSurfaceColor(theme),
            shape: shelfSurfaceShape(theme, corner),
            clipBehavior: Clip.antiAlias,
            child: tint == null
                ? ink
                : Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    includeSemantics: false,
                    child: Builder(
                      builder: (context) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ink,
                          if (Focus.of(context).hasFocus)
                            IgnorePointer(
                              // Inside the line of the card, which paints over
                              // its content and would hide half of the ring.
                              child: Padding(
                                padding: EdgeInsets.all(line),
                                child: DecoratedBox(
                                  key: const Key('shelfCardFocusRing'),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: tint.ink,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      corner - line,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// How a card of the grid wears the colour of its shelf: a band at the top in
/// its gradient, carrying the [fan] and the watermark, with the [text] at the
/// bottom of what is left, on the card itself.
class _ShelfCardBandDress extends StatelessWidget {
  static const double bandHeight = 88;

  /// The frame of a fan leaves its covers some room at the left: from here,
  /// their tilted edge lines up with the name.
  static const double fanLeft = 5;

  final ShelfTint tint;
  final Widget fan;
  final Widget text;

  const _ShelfCardBandDress({
    required this.tint,
    required this.fan,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: bandHeight,
          child: Ink(
            key: const Key('shelfCardGround'),
            decoration: BoxDecoration(
              gradient: AppDesign.shelfGradient(
                tint.ground,
                Theme.of(context).brightness,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.shelves,
                      key: const Key('shelfCardWatermark'),
                      size: 100,
                      color: AppDesign.shelfWatermarkColor,
                    ),
                  ),
                ),
                Positioned(left: fanLeft, top: 12, child: fan),
              ],
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ShelfCard._padding,
                0,
                ShelfCard._padding,
                ShelfCard._padding,
              ),
              child: text,
            ),
          ),
        ),
      ],
    );
  }
}

/// The number of sub-shelves of a card, on the line of its count. The label of
/// the card says it in a sentence.
class _SubShelvesMark extends StatelessWidget {
  final int count;
  final Color ink;

  const _SubShelvesMark({required this.count, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('shelfCardSubShelvesMark'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder, size: 13, color: ink),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: ShelfCard._countSize,
            fontWeight: FontWeight.w700,
            height: ShelfCard._countHeight,
            color: ink,
          ),
        ),
      ],
    );
  }
}
