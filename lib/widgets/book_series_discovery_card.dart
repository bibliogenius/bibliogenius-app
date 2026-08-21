import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import 'dashboard_section.dart';
import 'external_suggestion_sheet.dart';
import 'suggestion_tile.dart';

/// "Complete the series" on the book details page (ADR-061): the lowest
/// missing volume of a series this book belongs to, offered where the
/// reader has already expressed the matching intent.
///
/// Sits directly under the series frieze rather than at the bottom of the
/// page: the frieze is the series context, while the "You might also like"
/// carousel answers a different question (similar LOCAL books) and must
/// never absorb an external card.
///
/// CACHE-ONLY by design (ADR-061 section 2): rendering never fires a hub
/// lookup. Owned series are already swept by the dashboard, so the cache is
/// warm in normal use, and a second trigger surface would spend outbound
/// budget on a redundant answer. A series never swept simply shows nothing,
/// like every other discovery failure mode.
///
/// Exactly ONE card even when the book sits in several series collections
/// (a cycle plus an omnibus is legitimate, ADR-052). A dismissal reveals the
/// next missing ordinal of the SAME series, never jumps to another one.
class BookSeriesDiscoveryCard extends StatefulWidget {
  const BookSeriesDiscoveryCard({super.key, required this.seriesCollectionIds});

  /// Collection ids of the series-typed collections this book belongs to,
  /// in the order the details page holds them.
  final List<String> seriesCollectionIds;

  @override
  State<BookSeriesDiscoveryCard> createState() =>
      _BookSeriesDiscoveryCardState();
}

class _BookSeriesDiscoveryCardState extends State<BookSeriesDiscoveryCard> {
  /// Missing volumes of the chosen series, lowest ordinal first. The visible
  /// card is the first one that is not dismissed.
  List<Recommendation> _candidates = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant BookSeriesDiscoveryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The details screen is reused when navigating between books: refetch
    // when the series membership changes under us.
    if (!listEquals(
      oldWidget.seriesCollectionIds,
      widget.seriesCollectionIds,
    )) {
      setState(() => _candidates = const []);
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted || widget.seriesCollectionIds.isEmpty) return;
    final cards = await context
        .read<RecommendationProvider>()
        .seriesCardsForCollections(
          widget.seriesCollectionIds,
          langs: context.read<ThemeProvider>().userLanguages,
        );
    if (!mounted) return;
    setState(() => _candidates = cards);
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) return const SizedBox.shrink();

    // Narrow subscription: this card holds its own candidates and only
    // depends on the provider for dismissals.
    final dismissed = context.select<RecommendationProvider, Set<String>>(
      (provider) => provider.dismissedExternalKeys,
    );
    final card = _candidates
        .where((c) => !dismissed.contains(c.externalKey))
        .firstOrNull;
    if (card == null) return const SizedBox.shrink();
    final externalKey = card.externalKey;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDesign.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact header matching the frieze above, not the heavier
              // dashboard section header: the two read as one series block.
              FriezeSectionHeader(
                icon: Icons.library_add_outlined,
                title: TranslationService.translate(
                  context,
                  'series_discovery_header',
                ),
              ),
              const SizedBox(height: 12),
              FriezeCard(
                child: SuggestionTile(
                  suggestion: card,
                  onTap: () => ExternalSuggestionSheet.show(context, card),
                  onDismiss: externalKey == null
                      ? null
                      : () => dismissExternalSuggestionWithUndo(
                          context,
                          externalKey,
                        ),
                  dismissTooltip: TranslationService.translate(
                    context,
                    'recommendation_not_interested',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
