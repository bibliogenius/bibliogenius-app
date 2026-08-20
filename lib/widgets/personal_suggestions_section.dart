import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/recommendation_provider.dart';
import '../services/translation_service.dart';
import '../utils/recommendation_display.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/suggestion_tile.dart';

/// "Suggestions for you" on the dashboard: a short vertical list of unread
/// books scored against the user's taste profile, each with its reasons
/// (explainability is the trust contract of the feature, ADR-059).
///
/// Hidden when the profile is too thin (fewer than 5 scored books,
/// enforced Rust-side) or with fewer than 2 visible suggestions -- the
/// floor is evaluated AFTER filtering out "Not interested" dismissals.
/// Data comes from [RecommendationProvider], which caches, refreshes on
/// dashboard load, invalidates on catalogue mutations, and owns the
/// dismissal set. A "See all" link opens the full ranked list when the
/// digest cannot show everything.
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
    final provider = context.watch<RecommendationProvider>();
    if (provider.personal == null) return const SizedBox.shrink();

    final visible = provider.visiblePersonal;
    if (visible.length < _minSuggestions) {
      return const SizedBox.shrink();
    }
    final suggestions = visible.take(_maxDisplayed).toList();

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
            'recommendations_personal',
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Column(
            children: [
              for (var i = 0; i < suggestions.length; i++) ...[
                if (i > 0) const SuggestionSeparator(),
                SuggestionTile(
                  suggestion: suggestions[i],
                  onDismiss: switch (suggestions[i].book.id) {
                    null => null,
                    final bookId => () => dismissRecommendationWithUndo(
                      context,
                      bookId,
                    ),
                  },
                  dismissTooltip: dismissTooltip,
                ),
              ],
              // The full ranked list only earns a link when the digest
              // actually truncates it.
              if (visible.length > _maxDisplayed)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: SeeAllLink(
                    label: TranslationService.translate(
                      context,
                      'see_all_recommendations',
                    ),
                    onTap: () => context.push('/recommendations'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
