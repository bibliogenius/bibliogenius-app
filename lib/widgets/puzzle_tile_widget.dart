import 'package:flutter/material.dart';

import 'cached_book_cover.dart';

/// A single tile of the sliding puzzle.
///
/// Clips a portion of the book cover image using [FittedBox] + [Alignment]
/// to show only the section corresponding to this tile's position in the
/// solved state. A small, discrete number is displayed in the top-left corner.
class PuzzleTileWidget extends StatelessWidget {
  /// The tile number (1-based). 0 = empty space (should not be rendered).
  final int tileNumber;

  /// Grid size (e.g. 3 for 3x3).
  final int gridSize;

  /// URL of the full book cover image.
  final String coverUrl;

  /// Size of one tile in logical pixels.
  final double tileSize;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  const PuzzleTileWidget({
    super.key,
    required this.tileNumber,
    required this.gridSize,
    required this.coverUrl,
    required this.tileSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tileNumber == 0) {
      return const SizedBox.shrink();
    }

    // The tile's solved position (0-based index for tile number N is N-1)
    final solvedIndex = tileNumber - 1;
    final row = solvedIndex ~/ gridSize;
    final col = solvedIndex % gridSize;

    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: tileSize,
        height: tileSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 3,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Clipped portion of the cover image
              _buildClippedImage(row, col, colorScheme),
              // Discrete number in top-left corner
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$tileNumber',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: tileSize < 60 ? 8 : 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClippedImage(int row, int col, ColorScheme colorScheme) {
    // Use FittedBox + Alignment to show only the tile's portion of the image.
    // The alignment maps the tile's position to [-1, 1] range.
    final double alignX = gridSize == 1
        ? 0.0
        : -1.0 + 2.0 * col / (gridSize - 1);
    final double alignY = gridSize == 1
        ? 0.0
        : -1.0 + 2.0 * row / (gridSize - 1);

    return FittedBox(
      fit: BoxFit.none,
      alignment: Alignment(alignX, alignY),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: tileSize * gridSize,
        height: tileSize * gridSize,
        child: CachedBookCover(
          imageUrl: coverUrl,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.zero,
          errorWidget: Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.image,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
