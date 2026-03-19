import 'dart:math';

import 'package:flutter/material.dart';
import '../providers/hangman_provider.dart';

/// Displays the hangman visual (classic or book pyramid) based on error count.
class HangmanPainterWidget extends StatelessWidget {
  final int errors;
  final int maxErrors;
  final HangmanVisualMode visualMode;

  const HangmanPainterWidget({
    super.key,
    required this.errors,
    required this.maxErrors,
    required this.visualMode,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(260, 150),
      painter: visualMode == HangmanVisualMode.classic
          ? _ClassicHangmanPainter(errors: errors, theme: Theme.of(context))
          : _BookStackPainter(
              errors: errors,
              theme: Theme.of(context),
            ),
    );
  }
}

/// Classic hangman: gallows + 6 body parts.
class _ClassicHangmanPainter extends CustomPainter {
  final int errors;
  final ThemeData theme;

  _ClassicHangmanPainter({required this.errors, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.colorScheme.onSurface
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final bottom = size.height - 10;

    // Gallows (always visible)
    canvas.drawLine(Offset(cx - 50, bottom), Offset(cx + 20, bottom), paint);
    canvas.drawLine(Offset(cx - 30, bottom), Offset(cx - 30, 20), paint);
    canvas.drawLine(Offset(cx - 30, 20), Offset(cx + 30, 20), paint);
    canvas.drawLine(Offset(cx + 30, 20), Offset(cx + 30, 40), paint);

    final bodyPaint = Paint()
      ..color = theme.colorScheme.error
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (errors >= 1) {
      canvas.drawCircle(Offset(cx + 30, 52), 12, bodyPaint);
    }
    if (errors >= 2) {
      canvas.drawLine(Offset(cx + 30, 64), Offset(cx + 30, 100), bodyPaint);
    }
    if (errors >= 3) {
      canvas.drawLine(Offset(cx + 30, 72), Offset(cx + 10, 88), bodyPaint);
    }
    if (errors >= 4) {
      canvas.drawLine(Offset(cx + 30, 72), Offset(cx + 50, 88), bodyPaint);
    }
    if (errors >= 5) {
      canvas.drawLine(Offset(cx + 30, 100), Offset(cx + 14, 122), bodyPaint);
    }
    if (errors >= 6) {
      canvas.drawLine(Offset(cx + 30, 100), Offset(cx + 46, 122), bodyPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClassicHangmanPainter old) =>
      old.errors != errors;
}

/// 6 upright books on a shelf that topple one by one.
///
/// Each book is drawn vertically (like real books on a shelf) with:
/// - A colored cover face
/// - A visible spine edge with horizontal "page" lines
/// - A slight 3D perspective via parallelogram shape
/// Books topple from right to left on each error.
class _BookStackPainter extends CustomPainter {
  final int errors;
  final ThemeData theme;

  _BookStackPainter({required this.errors, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    // Vibrant, distinct book colors
    final colors = [
      const Color(0xFFD32F2F), // red
      const Color(0xFF1976D2), // blue
      const Color(0xFF388E3C), // green
      const Color(0xFFF57C00), // orange
      const Color(0xFF7B1FA2), // purple
      const Color(0xFF00796B), // teal
    ];

    final cx = size.width / 2;
    final bottom = size.height - 8;
    const shelfY = 2.0; // shelf line thickness

    // Shelf
    final shelfPaint = Paint()
      ..color = theme.colorScheme.onSurface.withValues(alpha: 0.2)
      ..strokeWidth = shelfY
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - 120, bottom),
      Offset(cx + 120, bottom),
      shelfPaint,
    );

    // Book dimensions
    const bookW = 28.0; // width (thickness when viewed from front)
    const bookH = 100.0; // height
    const spineW = 8.0; // visible spine depth (3D effect)
    const gap = 6.0;
    const totalW = (bookW + spineW + gap) * 6 - gap;
    final startX = cx - totalW / 2;

    for (var i = 0; i < 6; i++) {
      final x = startX + i * (bookW + spineW + gap);
      final bookBottom = bottom;
      final bookTop = bookBottom - bookH;
      final color = colors[i];

      // Toppled books (errors counted from right: book 5, 4, 3...)
      final bookIndex = 5 - i; // right-to-left removal
      final isFallen = errors > (5 - bookIndex);

      if (isFallen) {
        _drawFallenBook(canvas, cx, bookBottom, i, color);
      } else {
        _drawStandingBook(canvas, x, bookTop, bookBottom, bookW, spineW,
            bookH, color);
      }
    }
  }

  void _drawStandingBook(Canvas canvas, double x, double top, double bottom,
      double w, double spineW, double h, Color color) {
    final totalW = w + spineW;

    // Flat cover -- single rounded rectangle, no spine separation
    final coverPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final bookRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, top, totalW, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(bookRect, coverPaint);

    // Subtle bottom edge (pages visible at the bottom)
    final pagePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        x + 2, bottom - 3, x + totalW - 2, bottom,
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      ),
      pagePaint,
    );

    // Title area -- white rounded rectangle placeholder
    final titleBg = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final titleTop = top + h * 0.22;
    final titleBottom = top + h * 0.52;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x + 5, titleTop, x + totalW - 5, titleBottom),
        const Radius.circular(3),
      ),
      titleBg,
    );

    // Title lines inside the placeholder
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final lineCx = x + totalW / 2;
    canvas.drawLine(
      Offset(lineCx - 8, titleTop + (titleBottom - titleTop) * 0.35),
      Offset(lineCx + 8, titleTop + (titleBottom - titleTop) * 0.35),
      linePaint,
    );
    canvas.drawLine(
      Offset(lineCx - 5, titleTop + (titleBottom - titleTop) * 0.65),
      Offset(lineCx + 5, titleTop + (titleBottom - titleTop) * 0.65),
      linePaint,
    );
  }

  void _drawFallenBook(
      Canvas canvas, double cx, double bottom, int index, Color color) {
    // Fallen book lies flat on the shelf, slightly scattered
    final rng = Random(index * 42);
    final fallX = cx - 80 + index * 28.0 + rng.nextDouble() * 10;
    final fallAngle = (rng.nextDouble() - 0.5) * 0.5;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(fallX, bottom - 6);
    canvas.rotate(fallAngle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-14, -4, 28, 8),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BookStackPainter old) =>
      old.errors != errors;
}
