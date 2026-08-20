import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/book.dart';
import '../models/recommendation.dart';
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
/// (a single card is more noise than help).
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
    // engine should never emit any).
    final explained = recs.where((r) => r.reasons.isNotEmpty).toList();
    if (explained.length < _minRecommendations) return;
    setState(() => _recommendations = explained);
  }

  @override
  Widget build(BuildContext context) {
    if (_recommendations.length < _minRecommendations) {
      return const SizedBox.shrink();
    }

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
              itemCount: _recommendations.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppDesign.spacingMd),
              itemBuilder: (context, index) {
                final rec = _recommendations[index];
                return _RecommendationCard(
                  recommendation: rec,
                  width: _cardWidth,
                  coverHeight: _coverHeight,
                  onTap: () =>
                      context.push('/books/${rec.book.id}', extra: rec.book),
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
  });

  final Recommendation recommendation;
  final double width;
  final double coverHeight;
  final VoidCallback onTap;

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
      child: Semantics(
        button: true,
        // The card is read as one announcement; its inner Texts are already
        // summarized here.
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
            // Compact form: the icon carries "same author", the pill carries
            // the value, and the full sentence stays in the tooltip.
            Align(
              alignment: Alignment.centerLeft,
              child: ReasonChip(reason: reason, compact: true),
            ),
          ],
        ),
      ),
    );
  }
}
