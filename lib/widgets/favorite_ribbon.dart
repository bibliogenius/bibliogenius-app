import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The favorites marker (ADR-064): a teal bookmark ribbon with a bottom
/// notch, topped by a five-branch outline star, overhanging the TOP edge of
/// the tile it marks, "as a bookmark overhangs a book".
///
/// One drawing, every scale: book covers, the Favorites collection card
/// (type emblem over the mosaic) and the toggle icon all render through the
/// same painter, so the vocabulary stays strict (star bookmark = favorite,
/// heart = wished, pill = loan; ADR-063 owns the heart).
///
/// The marker is an INDICATOR: never make it tappable on cards. It carries
/// no semantics of its own; the host surface appends the translated
/// "favorite" fragment to its composed semantic label.
///
/// Meaning is carried by shape, not color alone (Rule A1 spirit): the star
/// head stays legible on any cover through its surface-colored fill. The
/// teal is fixed in both themes (validated mockup "Ruban favori"); the star
/// fill follows the theme surface, so dark themes keep a dark star head
/// with the teal outline.
const Color favoriteRibbonTeal = Color(0xFF3D8B83);

class FavoriteRibbon extends StatelessWidget {
  /// Ribbon body width; every other dimension derives from it. 12 is the
  /// book-cover scale, 14 the collection-card scale.
  final double width;

  const FavoriteRibbon({super.key, this.width = 12});

  /// Painted box width for a ribbon of body width [w] (the star head is
  /// wider than the body).
  static double boxWidthFor(double w) => 2 * (w * 0.65 + w * 0.115);

  /// Painted box height for a ribbon of body width [w].
  static double boxHeightFor(double w) => w * 3.8;

  /// Distance between the top of the painted box and the point where the
  /// host tile's TOP edge should sit: position the marker with
  /// `Positioned(top: -overhangFor(w), ...)` inside a
  /// `Stack(clipBehavior: Clip.none)` so the star emerges above the tile.
  static double overhangFor(double w) => w * 1.23;

  double get boxWidth => boxWidthFor(width);
  double get boxHeight => boxHeightFor(width);
  double get overhang => overhangFor(width);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(boxWidth, boxHeight),
        painter: FavoriteRibbonPainter(
          ribbonWidth: width,
          starFill: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

/// The toggle-button face: the same glyph at icon scale. Outline-only when
/// [active] is false (not a favorite), filled when true.
///
/// The toggle face is the ribbon's STAR HEAD alone, filling the icon
/// square: the full ribbon glyph keeps its 1:3.8 aspect and shrinks to a
/// few illegible pixels at button scale (recette feedback). The single
/// teal star stays the marker's identity and cannot be confused with the
/// amber rating-star row.
class FavoriteRibbonIcon extends StatelessWidget {
  final bool active;
  final double size;

  const FavoriteRibbonIcon({super.key, required this.active, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size),
        painter: FavoriteStarIconPainter(
          starFill: active
              ? favoriteRibbonTeal
              : Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

/// The star head alone, teal outline; the fill tells the toggle state
/// (surface = off, teal = on).
class FavoriteStarIconPainter extends CustomPainter {
  final Color starFill;

  const FavoriteStarIconPainter({required this.starFill});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final outerR = size.width / 2 - stroke;
    final star = starPath(
      size.width / 2,
      // The visual center of a 5-point star sits slightly above its
      // geometric box center; nudge down so it reads centered.
      size.height / 2 + outerR * 0.08,
      outerR,
      outerR * 0.44,
    );
    canvas.drawPath(star, Paint()..color = starFill);
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = favoriteRibbonTeal,
    );
  }

  @override
  bool shouldRepaint(FavoriteStarIconPainter oldDelegate) =>
      oldDelegate.starFill != starFill;
}

/// Draws the ribbon + star. Geometry is proportional to [ribbonWidth],
/// matching the validated mockup (body M16 20 h14 v34 with a 8px notch,
/// star r=9 stroke 1.6 at body width 14).
class FavoriteRibbonPainter extends CustomPainter {
  final double ribbonWidth;
  final Color starFill;

  /// Toggle-off face: the ribbon body is stroked, not filled.
  final bool outlineOnly;

  const FavoriteRibbonPainter({
    required this.ribbonWidth,
    required this.starFill,
    this.outlineOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = ribbonWidth;
    final stroke = w * 0.115;
    final outerR = w * 0.65;
    final innerR = outerR * 0.44;
    final cx = size.width / 2;
    final starCy = outerR + stroke;
    final ribbonTop = starCy + outerR * 0.93;
    final ribbonBottom = FavoriteRibbon.boxHeightFor(w);
    final notchDepth = w * 0.57;

    // Ribbon body: rectangle with a triangular bottom notch.
    final body = Path()
      ..moveTo(cx - w / 2, ribbonTop)
      ..lineTo(cx + w / 2, ribbonTop)
      ..lineTo(cx + w / 2, ribbonBottom)
      ..lineTo(cx, ribbonBottom - notchDepth)
      ..lineTo(cx - w / 2, ribbonBottom)
      ..close();

    if (outlineOnly) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..color = favoriteRibbonTeal,
      );
    } else {
      canvas.drawPath(body, Paint()..color = favoriteRibbonTeal);
      // Subtle edge so the teal reads on teal-ish covers.
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.064
          ..color = Colors.black.withValues(alpha: 0.18),
      );
      // Left highlight line, like light on a satin ribbon.
      canvas.drawLine(
        Offset(cx - w / 2 + w * 0.14, ribbonTop + w * 0.14),
        Offset(cx - w / 2 + w * 0.14, ribbonBottom - notchDepth - w * 0.36),
        Paint()
          ..strokeWidth = stroke
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }

    // Star head: surface fill, teal outline, round joins.
    final star = starPath(cx, starCy, outerR, innerR);
    canvas.drawPath(star, Paint()..color = starFill);
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = favoriteRibbonTeal,
    );
  }

  @override
  bool shouldRepaint(FavoriteRibbonPainter oldDelegate) =>
      oldDelegate.ribbonWidth != ribbonWidth ||
      oldDelegate.starFill != starFill ||
      oldDelegate.outlineOnly != outlineOnly;
}

/// Five-branch star path, top point up. Shared by the ribbon head and the
/// toggle-icon face so the two stars are the same drawing.
Path starPath(double cx, double cy, double outerR, double innerR) {
  const points = 5;
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outerR : innerR;
    // Start at the top point (-90 degrees), alternate outer/inner.
    final angle = (-90.0 + i * (360.0 / (points * 2))) * math.pi / 180.0;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}
