import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import '../utils/ownership_mark.dart';

/// Desaturates its child when [mark] says the book is not owned (ADR-063).
///
/// Full opacity, always: the state reads through the washed-out colors while
/// the cover stays perfectly legible; transparency is never used.
class OwnershipCoverTreatment extends StatelessWidget {
  final OwnershipMark mark;
  final Widget child;

  const OwnershipCoverTreatment({
    super.key,
    required this.mark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (mark == OwnershipMark.none) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(saturationMatrix(notOwnedSaturation)),
      child: child,
    );
  }
}

/// Small round badge naming the not-owned state; a heart for a wished book,
/// so a wish stays recognizable on top of the shared treatment (ADR-063).
/// Theme tokens only.
class OwnershipBadge extends StatelessWidget {
  final OwnershipMark mark;
  final double iconSize;

  const OwnershipBadge({super.key, required this.mark, this.iconSize = 13});

  @override
  Widget build(BuildContext context) {
    if (mark == OwnershipMark.none) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final wished = mark == OwnershipMark.wishedNotOwned;
    return Semantics(
      label: TranslationService.translate(
        context,
        wished ? 'reading_status_wanting' : 'not_owned',
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          wished ? Icons.favorite : Icons.bookmark_add_outlined,
          size: iconSize,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
