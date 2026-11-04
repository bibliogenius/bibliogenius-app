import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/book_genres.dart';
import 'cached_book_cover.dart';

/// The pair of colours a pictogram badge is drawn with.
@immutable
class ShelfTint {
  final Color background;
  final Color foreground;

  const ShelfTint(this.background, this.foreground);

  /// The tint of the shelf named [name]: a hue derived from the name, so a
  /// shelf keeps its colour on every device without anything being stored.
  ///
  /// Saturation and lightness are fixed per brightness, which is what keeps
  /// the pictogram readable whatever the hue (guarded for every hue in the
  /// thumbnail tests).
  factory ShelfTint.of(String name, Brightness brightness) {
    final hue = _hueOf(name);
    HSLColor hsl(double s, double l) => HSLColor.fromAHSL(1, hue, s, l);
    return brightness == Brightness.dark
        ? ShelfTint(hsl(0.28, 0.24).toColor(), hsl(0.50, 0.84).toColor())
        : ShelfTint(hsl(0.42, 0.87).toColor(), hsl(0.48, 0.26).toColor());
  }

  /// The ground of an empty shelf: the theme's own, no tint.
  factory ShelfTint.neutral(ColorScheme scheme) =>
      ShelfTint(scheme.surfaceContainerHighest, scheme.onSurfaceVariant);

  /// FNV-1a over the trimmed, lowercased name: stable across runs and
  /// platforms, unlike [String.hashCode].
  static double _hueOf(String name) {
    var hash = 0x811c9dc5;
    for (final unit in name.trim().toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return (hash % 360).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is ShelfTint &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}

/// The 72 x 56 picture at the head of a shelf row, the same in every shelf
/// tree.
///
/// Up to three covers fanned out when the shelf has some; otherwise a
/// pictogram badge: the genre's icon or the shelf icon on a tint of the
/// name when the shelf holds books, the shelf icon on a neutral ground when
/// it holds none. Decorative: the row already says the name and the count,
/// so nothing here reaches assistive technology.
class ShelfThumbnail extends StatelessWidget {
  static const double width = 72;
  static const double height = 56;

  final String name;

  /// Newest first, as the core lists them. Past three are ignored.
  final List<String> coverPaths;

  /// Whether the shelf or one of its sub-shelves holds a book, by the count
  /// the row prints.
  final bool hasBooks;

  const ShelfThumbnail({
    super.key,
    required this.name,
    required this.hasBooks,
    this.coverPaths = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        // The covers come from the core's subtree, the count from the tree
        // shown: a shelf counted empty here shows no book either.
        child: hasBooks && coverPaths.isNotEmpty
            ? _CoverFan(coverPaths.take(_maxCovers).toList())
            : _buildBadge(Theme.of(context)),
      ),
    );
  }

  Widget _buildBadge(ThemeData theme) {
    final tint = hasBooks
        ? ShelfTint.of(name, theme.brightness)
        : ShelfTint.neutral(theme.colorScheme);
    final icon = hasBooks
        ? genreIconForShelf(name) ?? Icons.shelves
        : Icons.shelves;
    return Container(
      key: const Key('shelfThumbnailBadge'),
      decoration: BoxDecoration(
        color: tint.background,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 28, color: tint.foreground),
    );
  }
}

const _maxCovers = 3;

/// Covers in a fan: 14 pt apart, turned -6, 0 and +6 degrees, centred in
/// the frame. The newest is drawn last, on top, at the right.
class _CoverFan extends StatelessWidget {
  final List<String> covers;

  const _CoverFan(this.covers);

  static const double _coverWidth = 38;
  static const double _coverHeight = 54;
  static const double _step = 14;

  static List<double> _anglesFor(int n) => switch (n) {
    1 => const [0],
    2 => const [-6, 6],
    _ => const [-6, 0, 6],
  };

  @override
  Widget build(BuildContext context) {
    final n = covers.length;
    final angles = _anglesFor(n);
    final spread = _coverWidth + _step * (n - 1);
    final left = (ShelfThumbnail.width - spread) / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var slot = 0; slot < n; slot++)
          Positioned(
            left: left + _step * slot,
            top: (ShelfThumbnail.height - _coverHeight) / 2,
            child: Transform.rotate(
              angle: angles[slot] * math.pi / 180,
              child: _cover(covers[n - 1 - slot]),
            ),
          ),
      ],
    );
  }

  Widget _cover(String path) {
    // Nothing in the slot while it loads or when it fails: a gap reads as
    // a shorter fan, a grey book would read as a broken one.
    const empty = SizedBox(width: _coverWidth, height: _coverHeight);
    return CachedBookCover(
      imageUrl: path,
      width: _coverWidth,
      height: _coverHeight,
      borderRadius: BorderRadius.circular(3),
      placeholder: empty,
      errorWidget: empty,
      semanticLabel: null,
    );
  }
}
