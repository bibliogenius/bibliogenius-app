import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../models/recommendation.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import 'cached_book_cover.dart';
import 'reason_chip.dart';

/// One personal suggestion row: cover, title, author and up to two reason
/// chips (explainability is the trust contract of the feature, ADR-059).
/// Shared by the dashboard "Suggestions for you" digest and the "See all"
/// screen so both surfaces speak the same visual language.
///
/// When [onDismiss] is set, the tile shows a close affordance ("Not
/// interested") in its top-right corner, following the GoalTile pattern.
class SuggestionTile extends StatelessWidget {
  const SuggestionTile({
    super.key,
    required this.suggestion,
    this.onDismiss,
    this.dismissTooltip,
  }) : assert(
         onDismiss == null || dismissTooltip != null,
         'a dismissible tile needs a translated dismissTooltip',
       );

  final Recommendation suggestion;

  /// Dismisses this suggestion ("Not interested"). The caller owns the
  /// persistence and the undo SnackBar.
  final VoidCallback? onDismiss;

  /// Already-translated tooltip / semantic label for the dismiss affordance.
  /// Required whenever [onDismiss] is set, so the button is never unlabelled
  /// for screen readers (Rules A1/A4).
  final String? dismissTooltip;

  static const double coverWidth = 44;
  static const double coverHeight = 66;
  static const double _horizontalPadding = 10;
  static const double _coverGap = 12;

  /// Left edge of the text column, shared with [SuggestionSeparator].
  static const double textOffset = _horizontalPadding + coverWidth + _coverGap;

  /// Screen-reader summary of the tile: what the eye reads in the title,
  /// author and chips, spoken once as a single button label.
  String _semanticsLabel(BuildContext context) {
    final book = suggestion.book;
    final reasons = suggestion.reasons
        .take(2)
        .map((r) => recommendationReasonSpokenLabel(context, r))
        .join(' · ');
    final author = book.author;
    return [
      book.title,
      if (author != null && author.isNotEmpty) author,
      reasons,
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final book = suggestion.book;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Semantics(
          button: true,
          // The inner Texts are already summarized in the label: excluding
          // them keeps the tile a single, clean announcement instead of an
          // echo. The dismiss button lives OUTSIDE this subtree so it keeps
          // its own semantics.
          excludeSemantics: true,
          label: _semanticsLabel(context),
          child: InkWell(
            onTap: () => context.push('/books/${book.id}', extra: book),
            borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: _horizontalPadding,
              ),
              child: Row(
                // Top-aligned: the cover lines up with the title, whatever
                // the number of reason chips underneath.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(book: book),
                  const SizedBox(width: _coverGap),
                  Expanded(
                    child: Padding(
                      // Keeps the title clear of the dismiss button parked
                      // in the top-right corner of the Stack.
                      padding: EdgeInsets.only(
                        right: onDismiss != null ? 28 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          if (book.author != null &&
                              book.author!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              book.author!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.2,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _ReasonChips(reasons: suggestion.reasons),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onDismiss != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: dismissTooltip,
              color: colorScheme.onSurfaceVariant,
              onPressed: onDismiss,
            ),
          ),
      ],
    );
  }
}

/// Hairline between two suggestions, inset so it starts at the text column
/// rather than cutting under the covers.
class SuggestionSeparator extends StatelessWidget {
  const SuggestionSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: SuggestionTile.textOffset,
        right: 10,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Cover thumbnail, or a neutral placeholder keeping the same footprint so the
/// text column never shifts between suggestions.
class _Cover extends StatelessWidget {
  const _Cover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverUrl = book.coverUrl;
    final hasCover = coverUrl != null && coverUrl.isNotEmpty;

    return Container(
      width: SuggestionTile.coverWidth,
      height: SuggestionTile.coverHeight,
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
          // Decorative here: the tile's own Semantics names the book.
          ? CachedBookCover(imageUrl: coverUrl, fit: BoxFit.cover)
          : Container(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.menu_book,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// Up to two "why this book" chips. They keep their natural width and wrap
/// onto a second line when the row is too narrow, rather than each taking half
/// the row and truncating mid-word.
class _ReasonChips extends StatelessWidget {
  const _ReasonChips({required this.reasons});

  final List<RecommendationReason> reasons;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final reason in reasons.take(2)) ReasonChip(reason: reason),
      ],
    );
  }
}
