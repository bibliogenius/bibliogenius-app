import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import 'shelf_thumbnail.dart';

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

/// A first-level shelf in the shelves tab: its fan of covers, its name, its
/// counts. One button, named by the shelf and its counts.
class ShelfCard extends StatelessWidget {
  static const double _padding = 12;
  static const double _gap = 8;
  static const double _nameGap = 2;
  static const int _maxLines = 2;

  final String name;
  final int books;
  final int subShelves;
  final List<String> coverPaths;

  /// The fan beside the text, for a single column.
  final bool horizontal;
  final VoidCallback onTap;

  const ShelfCard({
    super.key,
    required this.name,
    required this.books,
    required this.subShelves,
    required this.onTap,
    this.coverPaths = const [],
    this.horizontal = false,
  });

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
    final body = horizontal
        ? (text > tile ? text : tile)
        : tile + _gap + text;
    // A rounding margin: text metrics land a fraction above these sums.
    return body + _padding * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = shelfCountLabels(
      context,
      books: books,
      subShelves: subShelves,
    );
    final radius = BorderRadius.circular(18);

    final fan = ShelfThumbnail(
      size: ShelfThumbnailSize.l,
      hasBooks: books > 0,
      coverPaths: coverPaths,
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
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: _nameGap),
        Text(
          counts.join(' · '),
          maxLines: _maxLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: [name, ...counts].join(', '),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(_padding),
                child: horizontal
                    ? Row(
                        children: [
                          fan,
                          const SizedBox(width: _padding),
                          Expanded(child: text),
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
          ),
        ),
      ),
    );
  }
}
