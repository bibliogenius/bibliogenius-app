import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/recommendation_display.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/external_suggestion_sheet.dart';
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
///
/// External "complete the series" cards (ADR-060) blend into the same
/// list: at most 2 on the dashboard, appended after the locals so the
/// first local suggestions are never displaced, each with its source
/// badge and its pre-import tap flow.
class PersonalSuggestionsSection extends StatefulWidget {
  const PersonalSuggestionsSection({super.key});

  @override
  State<PersonalSuggestionsSection> createState() =>
      _PersonalSuggestionsSectionState();
}

class _PersonalSuggestionsSectionState
    extends State<PersonalSuggestionsSection> {
  /// The dashboard shows a digest, not the full ranked list. The floor it
  /// renders above lives on the provider, shared with the library slot.
  static const int _maxDisplayed = RecommendationProvider.dashboardMaxDisplayed;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: render the cached list now, refresh behind.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<RecommendationProvider>();
      await provider.loadPersonal();
      if (!mounted) return;
      // External sweep only after the local suggestions load (ADR-060
      // section 4.3: never blocking them). Reading languages drive the
      // hub-side edition filtering.
      await provider.loadExternal(
        langs: context.read<ThemeProvider>().userLanguages,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecommendationProvider>();
    if (provider.personal == null) return const SizedBox.shrink();

    if (!provider.hasVisibleSuggestions) {
      return const SizedBox.shrink();
    }
    // Blend (ADR-060 section 4.4): externals take at most 2 of the 5 slots
    // and sit after the locals, so the first local suggestions are never
    // displaced by discovery. The rule lives in the provider (ADR-062
    // section 5) so this digest and the library slot cannot drift apart.
    final suggestions = provider.blendedDigest(
      maxDisplayed: _maxDisplayed,
      maxExternal: RecommendationProvider.dashboardMaxExternal,
    );
    final truncated = provider.digestIsTruncated(
      maxDisplayed: _maxDisplayed,
      maxExternal: RecommendationProvider.dashboardMaxExternal,
    );

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
                  onTap: suggestions[i].isExternal
                      ? () => ExternalSuggestionSheet.show(
                          context,
                          suggestions[i],
                        )
                      : null,
                  onDismiss: switch ((
                    suggestions[i].externalKey,
                    suggestions[i].book.id,
                  )) {
                    (final String externalKey, _) =>
                      () => dismissExternalSuggestionWithUndo(
                        context,
                        externalKey,
                      ),
                    (null, final String bookId) =>
                      () => dismissRecommendationWithUndo(context, bookId),
                    _ => null,
                  },
                  dismissTooltip: dismissTooltip,
                ),
              ],
              // The full ranked list only earns a link when the digest
              // actually truncates it.
              if (truncated)
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
