import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'compact_suggestion_card.dart';
import 'external_suggestion_sheet.dart';
import 'recently_added_carousel.dart';

/// The shared slot at the top of the library screen (ADR-062 R3).
///
/// Activity and Suggestions answer opposite questions ("where was I?" and
/// "what next?"), so they share ONE height budget behind a lightweight
/// segmented header instead of stacking and pushing the book list below the
/// fold. Activity is the default and nothing ever auto-switches.
///
/// The slot owns no hide/collapse state of its own: it rides on the
/// carousel's, which is promoted from "the Activity strip" to "the whole
/// slot" (ADR-062 section 2). Hiding hides both segments, and the existing
/// Settings toggle restores both.
class BooksTopSlot extends StatelessWidget {
  const BooksTopSlot({super.key, required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final recommendations = context.watch<RecommendationProvider>();

    final hasActivity = RecentlyAddedCarousel.activitySelection(
      books,
    ).isNotEmpty;
    final suggestions = recommendations.hasVisibleSuggestions
        ? recommendations.blendedDigest(
            maxDisplayed: RecommendationProvider.slotMaxDisplayed,
            maxExternal: RecommendationProvider.slotMaxExternal,
          )
        : const <Recommendation>[];
    final hasDiscovery = suggestions.isNotEmpty;

    // No discovery to offer: the Activity carousel renders exactly as it
    // always has, header and all. This is the common case and the strongest
    // guarantee that the slot did not regress it.
    if (!hasDiscovery) {
      return RecentlyAddedCarousel(
        books: books,
        scope: RecentlyAddedCarouselScope.ownLib,
      );
    }

    // A segmented control with one dead half is noise: when Activity has
    // nothing, the discovery segment stands alone under a plain header.
    final showsDiscovery = hasActivity ? theme.booksSlotShowsDiscovery : true;
    // The count describes what the strip DRAWS, not what the provider holds.
    // Counting every visible suggestion instead used a different base from
    // the strip, which applies both a total cap and a tighter cap on
    // external cards: the two could never agree, and the header announced
    // more covers than the reader could find. The Activity segment has
    // always taken its count from the very selection it renders; this is
    // the same rule.
    final suggestionCount = suggestions.length;

    return RecentlyAddedCarousel(
      books: books,
      scope: RecentlyAddedCarouselScope.ownLib,
      headerTitle: _SlotHeader(
        showsDiscovery: showsDiscovery,
        hasActivity: hasActivity,
        activityCount: RecentlyAddedCarousel.activitySelection(books).length,
        suggestionCount: suggestionCount,
        onSelect: theme.setBooksSlotShowsDiscovery,
      ),
      bodyOverride: showsDiscovery
          ? _DiscoveryStrip(suggestions: suggestions)
          : null,
      collapsedSummary: showsDiscovery
          ? TranslationService.translate(
              context,
              'books_slot_segment_discover',
              params: {'count': suggestionCount.toString()},
            )
          : null,
    );
  }
}

/// The segmented header: two plain text tabs, the selected one carrying an
/// accent underline.
///
/// It shipped first as a Material [SegmentedButton], chosen for its free
/// selected-state semantics, and the first real render showed the trade was
/// wrong: the boxed control outweighed the covers it labels, and its pill
/// outline competed with the cards. The app already has a tab vocabulary
/// for exactly this (the library header switches Books / Shelves /
/// Collections with an underline), so the header now speaks it, at the same
/// text size as the plain Activity title it replaces. That keeps the slot's
/// header height identical whether or not a discovery segment exists.
///
/// The cost of dropping the Material control is that the selected state has
/// to be announced by hand (ADR-062 section 8 named this as the fallback).
/// Widget tests pin it: an accessibility regression here would be
/// invisible, since the tabs would still look correct.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({
    required this.showsDiscovery,
    required this.hasActivity,
    required this.activityCount,
    required this.suggestionCount,
    required this.onSelect,
  });

  final bool showsDiscovery;
  final bool hasActivity;
  final int activityCount;
  final int suggestionCount;
  final void Function(bool showsDiscovery) onSelect;

  @override
  Widget build(BuildContext context) {
    final discoverLabel = TranslationService.translate(
      context,
      'books_slot_segment_discover',
      params: {'count': suggestionCount.toString()},
    );

    // Only one segment has content: a plain header, no control to operate.
    if (!hasActivity) {
      return Semantics(
        header: true,
        child: Text(
          discoverLabel,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    final activityLabel = TranslationService.translate(
      context,
      'books_slot_segment_activity',
      params: {'count': activityCount.toString()},
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The icons are an enhancement, and the first thing to go when the
        // row runs out of room: below this the two labels plus their counts
        // already fill a narrow phone header beside the collapse chevron.
        final showIcons = constraints.maxWidth >= _iconsBreakpoint;
        return Row(
          children: [
            Flexible(
              child: _SlotTab(
                label: activityLabel,
                icon: Icons.auto_stories_rounded,
                showIcon: showIcons,
                selected: !showsDiscovery,
                onTap: () => onSelect(false),
              ),
            ),
            const SizedBox(width: AppDesign.spacingXs),
            Flexible(
              child: _SlotTab(
                label: discoverLabel,
                icon: Icons.auto_awesome,
                showIcon: showIcons,
                selected: showsDiscovery,
                onTap: () => onSelect(true),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Header width below which the tabs drop their icons.
  static const double _iconsBreakpoint = 260;
}

/// One tab of the slot header: icon, label, and a soft tonal background on
/// the selected one.
///
/// Only the selected tab carries a background, so nothing frames the pair
/// and nothing competes with the rounded cards below. State rests on three
/// signals at once (background, weight, colour) plus the icon, never on any
/// one of them alone. The icons are the ones the app already uses for these
/// two notions, so the header reads the same whether or not a discovery
/// segment exists: the Activity-only header shows that same open book.
class _SlotTab extends StatelessWidget {
  const _SlotTab({
    required this.label,
    required this.icon,
    required this.showIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool showIcon;
  final bool selected;
  final VoidCallback onTap;

  /// Comfortably hittable without making the header taller than the plain
  /// title it replaces.
  static const double _minHeight = 38;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusRound),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(AppDesign.radiusRound),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: selected ? colorScheme.primary : foreground,
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Flexible with an ellipsis rather than a fixed width: a
                  // long translation or a four-digit count must shorten the
                  // label, never overflow the header row.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: foreground,
                      ),
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

/// The discovery segment: a horizontal strip of compact cards plus the
/// link to the full list. Same height budget as the Activity strip so
/// switching segments never moves the book list below.
class _DiscoveryStrip extends StatelessWidget {
  const _DiscoveryStrip({required this.suggestions});

  final List<Recommendation> suggestions;

  @override
  Widget build(BuildContext context) {
    // The way to the full list rides at the END of the strip rather than on
    // a line of its own beneath it: same height budget, and it is found by
    // the same scroll that reads the cards.
    final itemCount = suggestions.length + 1;

    return SizedBox(
      height: CompactSuggestionCard.stripHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: AppDesign.spacingSm),
        itemBuilder: (context, index) {
          if (index == suggestions.length) {
            return SeeAllSuggestionsCard(
              label: TranslationService.translate(
                context,
                'see_all_recommendations',
              ),
            );
          }
          final suggestion = suggestions[index];
          return CompactSuggestionCard(
            suggestion: suggestion,
            onTap: suggestion.isExternal
                ? () => ExternalSuggestionSheet.show(context, suggestion)
                : null,
          );
        },
      ),
    );
  }
}
