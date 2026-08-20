import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import '../widgets/cached_book_cover.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/reason_chip.dart';

/// "Suggestions for you" on the dashboard: a short vertical list of unread
/// books scored against the user's taste profile, each with its reasons
/// (explainability is the trust contract of the feature, ADR-059).
///
/// Hidden when the profile is too thin (fewer than 5 scored books,
/// enforced Rust-side) or with fewer than 2 suggestions. Data comes from
/// [RecommendationProvider], which caches and refreshes on dashboard load
/// and invalidates on catalogue mutations.
class PersonalSuggestionsSection extends StatefulWidget {
  const PersonalSuggestionsSection({super.key});

  @override
  State<PersonalSuggestionsSection> createState() =>
      _PersonalSuggestionsSectionState();
}

class _PersonalSuggestionsSectionState
    extends State<PersonalSuggestionsSection> {
  static const int _minSuggestions = 2;

  /// The dashboard shows a digest, not the full ranked list.
  static const int _maxDisplayed = 5;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: render the cached list now, refresh behind.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RecommendationProvider>().loadPersonal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<RecommendationProvider>().personal;
    if (personal == null) return const SizedBox.shrink();

    final suggestions = personal.recommendations
        .where((r) => r.reasons.isNotEmpty)
        .take(_maxDisplayed)
        .toList();
    if (suggestions.length < _minSuggestions) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.auto_awesome,
          title: TranslationService.translate(
            context,
            'recommendations_personal',
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Column(
            children: [
              for (var i = 0; i < suggestions.length; i++) ...[
                if (i > 0) const _SuggestionSeparator(),
                _SuggestionTile(suggestion: suggestions[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Hairline between two suggestions, inset so it starts at the text column
/// rather than cutting under the covers.
class _SuggestionSeparator extends StatelessWidget {
  const _SuggestionSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: _SuggestionTile.textOffset,
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

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion});

  final Recommendation suggestion;

  static const double coverWidth = 44;
  static const double coverHeight = 66;
  static const double _horizontalPadding = 10;
  static const double _coverGap = 12;

  /// Left edge of the text column, shared with [_SuggestionSeparator].
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

    return Semantics(
      button: true,
      // The inner Texts are already summarized in the label: excluding them
      // keeps the tile a single, clean announcement instead of an echo.
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
            // Top-aligned: the cover lines up with the title, whatever the
            // number of reason chips underneath.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(book: book),
              const SizedBox(width: _coverGap),
              Expanded(
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
                    if (book.author != null && book.author!.isNotEmpty) ...[
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
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
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
      width: _SuggestionTile.coverWidth,
      height: _SuggestionTile.coverHeight,
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
