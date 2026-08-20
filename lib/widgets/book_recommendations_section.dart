import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/book.dart';
import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import 'book_cover_card.dart';
import 'dashboard_section.dart';
import 'reason_chip.dart';

/// "You might also like" on the book details page: a horizontal carousel
/// of local-library books similar to [book], each card carrying its reason
/// line (explainability is the trust contract of the feature, ADR-059).
///
/// Loads lazily after the details render (non-blocking) and renders
/// nothing while loading, on failure, or with fewer than 2 suggestions
/// (a single card is more noise than help). "Not interested" dismissals
/// come from [RecommendationProvider], apply to every recommendation
/// surface, and are filtered out BEFORE the two-suggestion floor.
class BookRecommendationsSection extends StatefulWidget {
  final Book book;

  const BookRecommendationsSection({super.key, required this.book});

  @override
  State<BookRecommendationsSection> createState() =>
      _BookRecommendationsSectionState();
}

class _BookRecommendationsSectionState
    extends State<BookRecommendationsSection> {
  static const int _minRecommendations = 2;
  static const double _cardWidth = 128;
  static const double _coverHeight = 176;

  /// Title (2 lines), author and reason chip under the cover, at text scale 1.
  static const double _metadataHeight = 84;

  List<Recommendation> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookRecommendationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The details screen is reused when navigating between similar books:
    // refetch when the reference changes.
    if (oldWidget.book.id != widget.book.id) {
      setState(() => _recommendations = []);
      _load();
    }
  }

  Future<void> _load() async {
    final bookId = widget.book.id;
    if (bookId == null) return;
    final repository = context.read<RecommendationRepository>();
    final recs = await repository.getBookRecommendations(bookId);
    if (!mounted) return;
    // Reasonless cards cannot be explained: drop them defensively (the
    // engine should never emit any). Dismissals are filtered at build time
    // so an Undo can bring a card back without refetching.
    setState(
      () => _recommendations = recs.where((r) => r.reasons.isNotEmpty).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Narrow subscription: this section has its own similar-books list and
    // only depends on the provider for dismissals, so select the dismissed
    // set instead of watching every provider notification.
    final dismissed = context.select<RecommendationProvider, Set<String>>(
      (provider) => provider.dismissedBookIds,
    );
    final visible = _recommendations
        .where((r) => !dismissed.contains(r.book.id))
        .toList();
    if (visible.length < _minRecommendations) {
      return const SizedBox.shrink();
    }

    final dismissTooltip = TranslationService.translate(
      context,
      'recommendation_not_interested',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.auto_awesome,
          title: TranslationService.translate(
            context,
            'recommendations_similar',
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            // Cover plus the text block, which follows the system text scale
            // so a large-text setting grows the row instead of clipping it.
            height:
                _coverHeight +
                MediaQuery.textScalerOf(context).scale(_metadataHeight),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppDesign.spacingMd),
              itemBuilder: (context, index) {
                final rec = visible[index];
                final bookId = rec.book.id;
                return _RecommendationCard(
                  recommendation: rec,
                  width: _cardWidth,
                  coverHeight: _coverHeight,
                  onTap: () =>
                      context.push('/books/${rec.book.id}', extra: rec.book),
                  onDismiss: bookId == null
                      ? null
                      : () => dismissRecommendationWithUndo(context, bookId),
                  dismissTooltip: dismissTooltip,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.width,
    required this.coverHeight,
    required this.onTap,
    this.onDismiss,
    this.dismissTooltip,
  }) : assert(
         onDismiss == null || dismissTooltip != null,
         'a dismissible card needs a translated dismissTooltip',
       );

  final Recommendation recommendation;
  final double width;
  final double coverHeight;
  final VoidCallback onTap;

  /// Dismisses this suggestion ("Not interested"); shown as a small close
  /// button over the cover corner, outside the card's summarized semantics
  /// so it keeps its own translated label (Rules A1/A4).
  final VoidCallback? onDismiss;
  final String? dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final book = recommendation.book;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final reason = recommendation.reasons.first;
    final reasonLabel = recommendationReasonSpokenLabel(context, reason);
    final author = book.author;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Semantics(
            button: true,
            // The card is read as one announcement; its inner Texts are
            // already summarized here. The dismiss button lives OUTSIDE
            // this subtree so it keeps its own semantics.
            excludeSemantics: true,
            label: [
              book.title,
              if (author != null && author.isNotEmpty) author,
              reasonLabel,
            ].join('. '),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight,
                  child: BookCoverCard(book: book, onTap: onTap),
                ),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (author != null && author.isNotEmpty)
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                // Compact form: the icon carries "same author", the pill
                // carries the value, and the full sentence stays in the
                // tooltip.
                Align(
                  alignment: Alignment.centerLeft,
                  child: ReasonChip(reason: reason, compact: true),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                icon: const Icon(Icons.close, size: 14),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: dismissTooltip,
                // Covers are arbitrary art: a translucent surface disc keeps
                // the icon above WCAG contrast whatever sits underneath.
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.85),
                  foregroundColor: colorScheme.onSurface,
                ),
                onPressed: onDismiss,
              ),
            ),
        ],
      ),
    );
  }
}
