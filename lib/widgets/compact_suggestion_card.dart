import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/recommendation.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import 'cached_book_cover.dart';
import 'suggestion_tile.dart';

/// One suggestion in the horizontal strip of the library top slot
/// (ADR-062 section 5): a bare cover, exactly like the Activity segment.
///
/// The slot has ONE visual language across both its segments, so switching
/// changes what is shown and never how it is shown, and the strip keeps one
/// height whatever the reader is looking at. A coverless book falls back to
/// its title inside the cover frame, the Activity strip's own fallback,
/// which is what keeps such a card identifiable with no caption underneath.
///
/// Two consequences, recorded in ADR-062 rather than slipped in. The reason
/// no longer rides on the card, where ADR-059 asks every card to show its
/// first one: it moves to the preview sheet a tap away, which already
/// prints it. And the title and author are visible only through the cover
/// art itself. Both remain in the screen-reader announcement, which is
/// [SuggestionTile]'s own so the two surfaces cannot drift apart.
class CompactSuggestionCard extends StatelessWidget {
  const CompactSuggestionCard({
    super.key,
    required this.suggestion,
    this.onTap,
  });

  final Recommendation suggestion;

  /// Overrides the default navigation to the book details. External cards
  /// (ADR-060) have no local book, so their callers pass the preview sheet.
  final VoidCallback? onTap;

  /// Matches the Activity strip's cover footprint, at its two sizes, so the
  /// two segments scroll to the same rhythm.
  static const double _coverWidth = 80;
  static const double _coverHeight = 120;
  static const double _coverWidthCompact = 64;
  static const double _coverHeightCompact = 96;
  static const double _compactBreakpoint = 360;

  static bool _isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < _compactBreakpoint;

  static double cardWidth(BuildContext context) =>
      _isCompact(context) ? _coverWidthCompact : _coverWidth;

  /// The cover, and nothing else. Nothing here scales with the text size
  /// because nothing here is text: the only words are the fallback title,
  /// which lives INSIDE the cover and ellipsizes within it.
  static double stripHeight(BuildContext context) =>
      _isCompact(context) ? _coverHeightCompact : _coverHeight;

  @override
  Widget build(BuildContext context) {
    final book = suggestion.book;
    final compact = _isCompact(context);

    return Semantics(
      button: true,
      // The cover carries no words, so this label is the ONLY place the
      // title, author, source and reason are spoken. It is the tile's own
      // label, so the two surfaces cannot drift apart.
      excludeSemantics: true,
      label: SuggestionTile.semanticsLabel(context, suggestion),
      child: InkWell(
        onTap: onTap ?? () => context.push('/books/${book.id}', extra: book),
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        child: _MarkedCover(
          suggestion: suggestion,
          width: compact ? _coverWidthCompact : _coverWidth,
          height: compact ? _coverHeightCompact : _coverHeight,
        ),
      ),
    );
  }
}

/// The cover, carrying the source marker in its corner when the book is not
/// in the library. A corner marker is the Activity strip's own idiom for
/// state, so the two segments mark their covers the same way.
///
/// Icon-only by necessity at this size, with the wording on hover and in the
/// card's single screen-reader label, never as the sole carrier of meaning.
class _MarkedCover extends StatelessWidget {
  const _MarkedCover({
    required this.suggestion,
    required this.width,
    required this.height,
  });

  final Recommendation suggestion;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final book = suggestion.book;
    final coverUrl = book.coverUrl;
    final hasCover = coverUrl != null && coverUrl.isNotEmpty;

    final cover = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        boxShadow: AppDesign.subtleShadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.6)),
      ),
      child: hasCover
          // Decorative: the card's own Semantics names the book.
          ? CachedBookCover(imageUrl: coverUrl, fit: BoxFit.cover)
          // The Activity strip's own fallback: with no image and no caption
          // underneath, a placeholder icon would leave the card
          // unidentifiable, so the title takes the cover's place.
          : Container(
              color: colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(6),
              child: Text(
                book.title,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
            ),
    );

    final badgeLabel = recommendationSourceBadgeLabel(
      context,
      suggestion.source,
    );
    final author = book.author;
    // A cover-only display hides the two things that identify a book, so
    // they come back on hover and on long-press, through the same Tooltip
    // idiom the collection stacks already use for their cover-only tiles.
    // Not a pointer-only affordance: a Tooltip answers a long press too.
    final tooltip = [
      book.title,
      if (author != null && author.isNotEmpty) author,
      if (badgeLabel != null) badgeLabel,
    ].join('\n');

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Stack(
        children: [
          cover,
          if (badgeLabel != null)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colorScheme.tertiary,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: Icon(
                Icons.explore_outlined,
                size: 11,
                color: colorScheme.onTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trailing card of the discovery strip: the way to the full ranked list,
/// riding in the scroll rather than costing the slot a whole line beneath
/// it. Tonal so it reads as an action, not as another book.
class SeeAllSuggestionsCard extends StatelessWidget {
  const SeeAllSuggestionsCard({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = CompactSuggestionCard.cardWidth(context);

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: CompactSuggestionCard.stripHeight(context),
        child: Material(
          color: colorScheme.primary.withValues(alpha: 0.07),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.20),
            ),
            borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
          ),
          child: InkWell(
            onTap: () => context.push('/recommendations'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
