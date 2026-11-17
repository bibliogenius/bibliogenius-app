import 'package:flutter/material.dart';

import 'cover_grid_delegate.dart';

/// Miniature of the library covers grid at the cover size [coverSize]: the
/// grid's own delegate laid out at the library's width on this screen, then
/// scaled down to the space given. Plain tiles stand for the covers.
///
/// Its height is fixed and the rows past it are cut off, so that a slider
/// below it does not move while the size changes under the finger.
class CoverSizePreview extends StatelessWidget {
  const CoverSizePreview({super.key, required this.coverSize});

  final double coverSize;

  static const double height = 120;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tileColors = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    final gridWidth = coverGridWidthOf(context);
    final delegate = CoverGridDelegate(
      coverSize: coverSize,
      childAspectRatio: coverGridAspectRatio,
      phone: coverGridIsPhone(context),
    );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / gridWidth;
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: gridWidth,
                height: height / scale,
                child: GridView.builder(
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: delegate,
                  // Endless: the grid builds only the tiles that show.
                  itemBuilder: (context, index) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: tileColors[index % tileColors.length],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
