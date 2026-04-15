import 'package:flutter/material.dart';
import 'dart:math';
import '../models/book.dart';
import '../services/translation_service.dart';
import '../utils/book_color_seed.dart';

/// A book spine widget that renders a colored vertical strip with the title.
///
/// Can be constructed from either a full [Book] object or minimal data
/// (title + optional author + color seed). The color is deterministic
/// based on the seed value.
class BookSpine extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int colorSeed;
  final double height;
  final double width;
  final double opacity;
  /// When true, shows a publisher-style band ("Nouveau") at the bottom.
  final bool showNewBand;

  /// Creates a spine from a full [Book] object.
  BookSpine.fromBook({
    super.key,
    required Book book,
    this.height = 150,
    this.width = 40,
    this.showNewBand = false,
  })  : title = book.title,
        subtitle = book.publisher,
        colorSeed = bookColorSeed(book),
        opacity = book.owned ? 1.0 : 0.5;

  /// Creates a spine from minimal data (title + optional author/subtitle).
  /// [colorSeed] is used to generate a deterministic color (e.g. ISBN hashCode).
  const BookSpine({
    super.key,
    required this.title,
    this.subtitle,
    required this.colorSeed,
    this.height = 150,
    this.width = 40,
    this.opacity = 1.0,
    this.showNewBand = false,
  });

  Color _getColor() {
    final random = Random(colorSeed);
    return Color.fromARGB(
      255,
      random.nextInt(200), // Darker colors look more like books
      random.nextInt(200),
      random.nextInt(200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = _getColor();

    final spine = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(2),
          bottomRight: Radius.circular(2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(1, 1),
            blurRadius: 2,
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            baseColor.withValues(alpha: 0.8),
            baseColor,
            baseColor.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.2, 0.9],
        ),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3, // Rotate 270 degrees (bottom to top)
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: showNewBand ? 5 : 3),
      child: Semantics(
        label: subtitle != null ? '$title, $subtitle' : title,
        child: Opacity(
          opacity: opacity,
          child: showNewBand
              ? SizedBox(
                  height: height,
                  width: width,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      spine,
                      Positioned(
                        bottom: height * 0.04,
                        left: -3,
                        right: -3,
                        child: Transform.rotate(
                          angle: -0.10, // slight tilt like a real paper band
                          child: _NewBand(spineWidth: width),
                        ),
                      ),
                    ],
                  ),
                )
              : spine,
        ),
      ),
    );
  }
}

/// Publisher-style paper band overlaid on the spine bottom.
class _NewBand extends StatelessWidget {
  final double spineWidth;
  const _NewBand({required this.spineWidth});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: spineWidth + 8, // extend beyond spine edges
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFC62828), // deep red
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Text(
        TranslationService.translate(context, 'badge_new').toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          height: 1,
        ),
      ),
    );
  }
}
