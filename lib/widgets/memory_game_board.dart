import 'package:flutter/material.dart';

import '../models/memory_game.dart';
import 'memory_card_widget.dart';

/// Responsive grid board for the memory game.
///
/// Adapts column count based on card count and screen size.
/// Cards maintain a book cover aspect ratio (~2:3).
class MemoryGameBoard extends StatelessWidget {
  final List<MemoryCard> cards;
  final ValueChanged<int> onCardTap;

  const MemoryGameBoard({
    super.key,
    required this.cards,
    required this.onCardTap,
  });

  /// Determine column count based on total cards and available width.
  ///
  /// Adapts to available space: on wide screens, uses more columns
  /// to fill the space. Always ensures cards divide evenly when possible.
  int _columnCount(double availableWidth) {
    final totalCards = cards.length;

    // Minimum columns based on card count
    final minCols = totalCards <= 6
        ? 3
        : totalCards <= 12
        ? 3
        : totalCards <= 16
        ? 4
        : 5;

    // Target card width for good visual (~100-120px)
    const targetCardWidth = 110.0;
    final maxCols = (availableWidth / targetCardWidth).floor().clamp(
      minCols,
      10,
    );

    // Find the best column count that divides evenly (prefer larger)
    for (int cols = maxCols; cols >= minCols; cols--) {
      if (totalCards % cols == 0) return cols;
    }
    return maxCols;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth);
        final spacing = 8.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns + 1)) / columns;
        final cardHeight = cardWidth * 1.4; // ~2:3 book cover ratio

        return GridView.builder(
          padding: EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            return MemoryCardWidget(
              card: cards[index],
              onTap: () => onCardTap(index),
            );
          },
        );
      },
    );
  }
}
