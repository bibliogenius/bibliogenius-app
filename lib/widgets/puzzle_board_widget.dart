import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sliding_puzzle_provider.dart';
import 'puzzle_tile_widget.dart';

/// The sliding puzzle board.
///
/// Uses a [Stack] with [AnimatedPositioned] for smooth tile sliding
/// (150ms, easeOutCubic). The board is a square that fits within
/// the available space.
class PuzzleBoardWidget extends StatelessWidget {
  const PuzzleBoardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SlidingPuzzleProvider>(
      builder: (context, provider, child) {
        final gridSize = provider.gridSize;
        final tiles = provider.tiles;
        final coverUrl = provider.board?.coverUrl ?? '';

        if (tiles.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Board is a square that fits available width/height
            final maxSize = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            final boardSize = maxSize.clamp(0.0, 500.0);
            const spacing = 3.0;
            final tileSize = (boardSize - spacing * (gridSize - 1)) / gridSize;

            return SizedBox(
              width: boardSize,
              height: boardSize,
              child: Stack(
                children: List.generate(tiles.length, (index) {
                  final tileNum = tiles[index];
                  if (tileNum == 0) {
                    return const SizedBox.shrink();
                  }

                  final row = index ~/ gridSize;
                  final col = index % gridSize;
                  final left = col * (tileSize + spacing);
                  final top = row * (tileSize + spacing);

                  return AnimatedPositioned(
                    key: ValueKey(tileNum),
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    left: left,
                    top: top,
                    child: PuzzleTileWidget(
                      tileNumber: tileNum,
                      gridSize: gridSize,
                      coverUrl: coverUrl,
                      tileSize: tileSize,
                      onTap: provider.phase == PuzzlePhase.playing
                          ? () => provider.moveTile(index)
                          : null,
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }
}
