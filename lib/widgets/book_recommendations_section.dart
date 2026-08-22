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
///
/// Caps itself at [AppDesign.maxContentWidth]: the book-details page has no
/// page-level width cap of its own, so on a wide tablet/desktop window this
/// carousel of fixed-size cards would otherwise stretch its card edge to
/// edge for no visual gain.
class BookRecommendationsSection extends StatefulWidget {
  final Book book;

  /// Heading of the section. Overridden when the section is PROMOTED to the
  /// top of the page at the moment a book is marked read (ADR-062 R5): the
  /// same "books like this one" answers a different question there, so it
  /// changes its wording, not its content. Promotion rather than a second
  /// block: two rows of covers on one page read as duplication whatever
  /// their data sources are.
  final String titleKey;

  const BookRecommendationsSection({
    super.key,
    required this.book,
    this.titleKey = 'recommendations_similar',
  });

  @override
  State<BookRecommendationsSection> createState() =>
      _BookRecommendationsSectionState();
}

class _BookRecommendationsSectionState
    extends State<BookRecommendationsSection> {
  static const int _minRecommendations = 2;
  static const double _cardWidth = 128;
  static const double _coverHeight = 176;

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

    // Unlike the dashboard, the book-details page has no page-level content
    // cap: on a wide tablet/desktop window this small, fixed-size-card
    // carousel would otherwise stretch its surrounding card edge to edge,
    // leaving a wide dead strip next to a handful of 128px covers. Cap it
    // to the app's standard content width and keep it left-aligned, matching
    // the page's own left-aligned column, instead of centering an orphaned
    // block.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDesign.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.auto_awesome,
              title: TranslationService.translate(context, widget.titleKey),
            ),
            const SizedBox(height: 16),
            SectionCard(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                // Cover plus the text block, whose height the card computes
                // from its own reserved slots: they follow the system text
                // scale, so a large-text setting grows the row instead of
                // clipping it.
                height:
                    _coverHeight + _RecommendationCard.metadataHeight(context),
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
                      onTap: () => context.push(
                        '/books/${rec.book.id}',
                        extra: rec.book,
                      ),
                      onDismiss: bookId == null
                          ? null
                          : () =>
                                dismissRecommendationWithUndo(context, bookId),
                      dismissTooltip: dismissTooltip,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
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

  static const double _coverGap = 10;
  static const double _authorGap = 2;
  static const double _chipGap = 8;
  static const int _titleLines = 2;
  static const double _lineHeight = 1.25;
  static const double _dismissSize = 30;

  /// Height of the caption block under the cover.
  ///
  /// Every slot is reserved whatever this card actually carries -- two title
  /// lines even for a one-line title, the author line even when the book has
  /// no author -- so the authors and the reason chips of the whole row land
  /// on the same two lines. Without it a wrapping title dropped its own
  /// card's caption one line below its neighbours'.
  static double metadataHeight(BuildContext context) {
    return _coverGap +
        _titleLineHeight(context) * _titleLines +
        _authorGap +
        _authorLineHeight(context) +
        _chipGap +
        ReasonChip.height(context);
  }

  static double _titleLineHeight(BuildContext context) =>
      _scaledLine(context, Theme.of(context).textTheme.labelMedium?.fontSize);

  static double _authorLineHeight(BuildContext context) =>
      _scaledLine(context, Theme.of(context).textTheme.labelSmall?.fontSize);

  /// Both caption styles pin [_lineHeight], so their laid-out line height is
  /// the scaled font size times that factor -- no font metrics in the
  /// reservation above -- rounded up like the text engine rounds a line.
  static double _scaledLine(BuildContext context, double? fontSize) =>
      (MediaQuery.textScalerOf(context).scale(fontSize ?? 12) * _lineHeight)
          .ceilToDouble();

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
            // The whole card is the target, not just the cover: the caption
            // under a cover is where a pointer naturally lands, and the
            // semantics above already announce the card as one button.
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: coverHeight,
                    width: width,
                    // Hairline frame: book covers are very often near-white
                    // at the edges and would otherwise dissolve into the
                    // section's white surface. Same treatment as the
                    // suggestion tiles on the dashboard.
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppDesign.radiusSmall,
                        ),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                      child: BookCoverCard(book: book, onTap: onTap),
                    ),
                  ),
                  const SizedBox(height: _coverGap),
                  SizedBox(
                    height: _titleLineHeight(context) * _titleLines,
                    child: Text(
                      book.title,
                      maxLines: _titleLines,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: _lineHeight,
                      ),
                    ),
                  ),
                  const SizedBox(height: _authorGap),
                  SizedBox(
                    height: _authorLineHeight(context),
                    child: Text(
                      author ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: _lineHeight,
                      ),
                    ),
                  ),
                  const SizedBox(height: _chipGap),
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
          ),
          if (onDismiss != null)
            Positioned(
              // Bottom-right of the cover. The top-right corner belongs to
              // the reading-status pill, which a button parked there used to
              // sit on top of and clip.
              top: coverHeight - _dismissSize - 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, size: 15),
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: _dismissSize,
                  height: _dismissSize,
                ),
                tooltip: dismissTooltip,
                // Covers are arbitrary art: an opaque disc with its own
                // outline keeps the icon above WCAG contrast whatever sits
                // underneath, and reads as a control rather than as part of
                // the artwork.
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.92),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: const CircleBorder(),
                  side: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                onPressed: onDismiss,
              ),
            ),
        ],
      ),
    );
  }
}
