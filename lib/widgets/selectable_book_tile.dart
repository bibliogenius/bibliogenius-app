import 'package:flutter/material.dart';

import '../theme/app_design.dart';

/// Wraps a book tile so it can take part in a multi-selection.
///
/// Outside selection mode ([selected] is null) the tile behaves as usual and
/// a long press enters selection mode (a pointer shortcut; the screen
/// provides a labelled button for the same thing). In selection mode the
/// whole tile becomes one toggle: the wrapped card's own gestures (open the
/// book, change its status) are suspended so a tap can only mean "select".
class SelectableBookTile extends StatelessWidget {
  final Widget child;

  /// Null outside selection mode; otherwise whether this book is selected.
  final bool? selected;

  /// What the screen reader announces for the tile in selection mode
  /// (title and author): the wrapped card's semantics are suspended with
  /// its gestures.
  final String semanticLabel;

  final VoidCallback? onToggle;
  final VoidCallback? onLongPress;

  const SelectableBookTile({
    super.key,
    required this.child,
    required this.selected,
    required this.semanticLabel,
    this.onToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected;
    if (isSelected == null) {
      if (onLongPress == null) return child;
      // Kept out of the semantics tree: a second node around the card would
      // split its name from its role. Screen reader users enter selection
      // mode through the labelled button of the filter bar.
      return GestureDetector(
        onLongPress: onLongPress,
        excludeFromSemantics: true,
        child: child,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      onTap: onToggle,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Stack(
          children: [
            IgnorePointer(child: child),
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(
                        AppDesign.radiusSmall,
                      ),
                      border: Border.all(color: scheme.primary, width: 3),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? scheme.primary : scheme.surface,
                  border: Border.all(
                    color: isSelected ? scheme.primary : scheme.outline,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
