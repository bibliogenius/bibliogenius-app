import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'shelf_fan_flight.dart';
import 'shelf_thumbnail.dart';

/// The ground of a shelf surface: that of the theme's cards.
Color shelfSurfaceColor(ThemeData theme) =>
    theme.cardTheme.color ?? theme.cardColor;

/// The outline of a shelf surface: the line of the theme's cards, around the
/// corners the shelves keep whatever the theme.
ShapeBorder shelfSurfaceShape(ThemeData theme, double radius) {
  final themed = theme.cardTheme.shape;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: themed is OutlinedBorder ? themed.side : BorderSide.none,
  );
}

/// How many columns of shelf cards fit [width]: one on a very narrow screen
/// or with large text, where two would cut the names short.
int shelfGridColumns({required double width, required double textScale}) {
  if (width < 360 || textScale >= 1.3) return 1;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
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
/// On the grid it wears the colour of its shelf, and the icon of a shelf where
/// there is no cover to show. The small form stays on the theme's card.
class ShelfCard extends StatelessWidget {
  static const double _padding = 12;
  static const double _gap = 8;
  static const double _nameGap = 2;
  static const int _maxLines = 2;

  /// What picks the colour of the card; the small form has none.
  final String? shelfId;
  final String name;
  final int books;
  final int subShelves;
  final List<String> coverPaths;

  /// The fan beside the text, for a single column.
  final bool horizontal;

  /// The small form, for a sub-shelf on a shelf's page.
  final bool compact;
  final VoidCallback onTap;

  /// Sends the fan off on its way to the shelf's page, on a tap.
  final ShelfFanFlight? flight;

  const ShelfCard({
    super.key,
    required String this.shelfId,
    required this.name,
    required this.books,
    required this.subShelves,
    required this.onTap,
    this.coverPaths = const [],
    this.horizontal = false,
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
  }) : shelfId = null,
       horizontal = true,
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

  /// The height of a grid row: room for two lines of name and of counts at
  /// the text scale in use, so that no card overflows and rows stay aligned.
  static double extentFor(BuildContext context, {required bool horizontal}) {
    final theme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double lines(TextStyle? style) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.4) * _maxLines;
    }

    final text = lines(theme.titleMedium) + _nameGap + lines(theme.bodySmall);
    const tile = 66.0;
    final body = horizontal ? (text > tile ? text : tile) : tile + _gap + text;
    // A rounding margin: text metrics land a fraction above these sums.
    return body + _padding * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = shelfCountLabels(
      context,
      books: books,
      subShelves: subShelves,
    );
    final corner = compact ? 14.0 : 18.0;
    final tint = compact ? null : AppDesign.shelfTint(shelfId!, theme.brightness);

    final fanSize = compact ? ShelfThumbnailSize.s : ShelfThumbnailSize.l;
    // On the grid, nothing flies from the icon of a shelf with no cover to show.
    final flies = compact || (books > 0 && coverPaths.isNotEmpty);
    late BuildContext fanContext;
    final fan = !compact && !flies
        ? _ShelfIcon(hasSubShelves: subShelves > 0, centred: horizontal)
        : Builder(
            builder: (context) {
              fanContext = context;
              return ShelfThumbnail(
                size: fanSize,
                hasBooks: books > 0,
                coverPaths: coverPaths,
              );
            },
          );
    // The small form prints only a bare number, at the right: the sentence would
    // compete with the count of the head. A screen reader still gets it whole.
    final Widget text = compact
        ? Text(
            name,
            maxLines: _maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: _maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: _nameGap),
              Text(
                counts.join(' · '),
                maxLines: _maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          );

    final ink = InkWell(
      // The theme's overlays are made for its surfaces: on a colour they vanish.
      splashColor: tint == null ? null : Colors.white.withValues(alpha: 0.24),
      highlightColor: tint == null ? null : Colors.white.withValues(alpha: 0.12),
      hoverColor: tint == null ? null : Colors.white.withValues(alpha: 0.12),
      focusColor: tint == null ? null : Colors.white.withValues(alpha: 0.24),
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
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
              : const EdgeInsets.all(_padding),
          child: horizontal
              ? Row(
                  children: [
                    fan,
                    SizedBox(width: compact ? 10 : _padding),
                    Expanded(child: text),
                    if (compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$books',
                        // The theme's own muted colour: its
                        // onSurfaceVariant can be the name's.
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fan,
                    const SizedBox(height: _gap),
                    Flexible(child: text),
                  ],
                ),
        ),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: [name, ...counts].join(', '),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(corner),
            boxShadow: tint == null
                ? AppDesign.subtleShadow
                : [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.28),
                      offset: const Offset(0, 6),
                      blurRadius: 14,
                    ),
                  ],
          ),
          child: tint == null
              ? Material(
                  color: shelfSurfaceColor(theme),
                  shape: shelfSurfaceShape(theme, corner),
                  clipBehavior: Clip.antiAlias,
                  child: ink,
                )
              : Material(
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(corner),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    key: const Key('shelfCardGround'),
                    decoration: BoxDecoration(
                      gradient: AppDesign.shelfGradient(tint),
                    ),
                    child: ink,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The picture of a shelf with no cover to show, in the frame of a fan so that
/// the names of a row line up.
class _ShelfIcon extends StatelessWidget {
  final bool hasSubShelves;
  final bool centred;

  const _ShelfIcon({required this.hasSubShelves, required this.centred});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 66,
      child: Align(
        alignment: centred ? Alignment.centerLeft : Alignment.topLeft,
        child: Container(
          key: const Key('shelfCardIcon'),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            hasSubShelves ? Icons.folder : Icons.label,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
