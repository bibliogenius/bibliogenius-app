import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/external_suggestion_sheet.dart';
import '../widgets/suggestion_tile.dart';

/// "See all" for the personal suggestions (ADR-059 follow-up): the full
/// ranked list the dashboard digest truncates, reusing the same
/// [RecommendationProvider] cache and the same tiles, including the
/// "Not interested" dismissal with its SnackBar Undo. External discovery
/// cards (ADR-060) append after the locals, capped at 10, with the same
/// badge, dismissal and pre-import tap flow as the dashboard.
///
/// The page deliberately carries what the digest has no room for: the
/// taste profile the picks rest on. Explainability is the trust contract
/// of the feature (ADR-059), the profile arrives in the same payload as
/// the list, and a full page is where a reader goes to ask "why these?".
///
/// One list, never two sections: blending locals and discoveries is a
/// decided design position (`recommendations-blended-suggestions-ux.md`
/// section 2), with the source carried per card instead.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate, same as the dashboard section: the cached
    // list renders instantly, a refresh runs behind if it went stale.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final provider = context.read<RecommendationProvider>();
    await provider.loadPersonal(force: force);
    if (!mounted) return;
    await provider.loadExternal(
      langs: context.read<ThemeProvider>().userLanguages,
      force: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecommendationProvider>();
    // Single blended list: locals in engine order, then the external cards
    // capped at 10 (ADR-060 section 4.4).
    final suggestions = [
      ...provider.visiblePersonal,
      ...provider.visibleExternal.take(
        RecommendationProvider.seeAllMaxExternal,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'recommendations_personal'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: _buildBody(context, provider, suggestions),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RecommendationProvider provider,
    List<Recommendation> suggestions,
  ) {
    if (provider.isLoadingFirstPersonal) {
      return Semantics(
        label: TranslationService.translate(context, 'recommendations_loading'),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (suggestions.isEmpty) {
      return _EmptyState();
    }

    final dismissTooltip = TranslationService.translate(
      context,
      'recommendation_not_interested',
    );

    return ListView(
      // Always scrollable, so pull-to-refresh works on a short list too.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        // Reading rows stretched across a desktop window are unreadable and
        // leave the covers marooned at the far left. Cap and centre, the
        // app's standard content width.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDesign.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BasisCard(profile: provider.personal),
                SectionCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 6,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < suggestions.length; i++) ...[
                        if (i > 0) const SuggestionSeparator(),
                        _tile(context, suggestions[i], dismissTooltip),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    Recommendation suggestion,
    String dismissTooltip,
  ) {
    final bookId = suggestion.book.id;
    final externalKey = suggestion.externalKey;
    return SuggestionTile(
      suggestion: suggestion,
      onTap: suggestion.isExternal
          ? () => ExternalSuggestionSheet.show(context, suggestion)
          : null,
      onDismiss: externalKey != null
          ? () => dismissExternalSuggestionWithUndo(context, externalKey)
          : bookId == null
          ? null
          : () => dismissRecommendationWithUndo(context, bookId),
      dismissTooltip: dismissTooltip,
    );
  }
}

/// What the picks rest on: how many read books fed the profile, and the
/// authors and subjects it drew out. Renders nothing when the profile has
/// none of the three, rather than an empty frame.
class _BasisCard extends StatelessWidget {
  const _BasisCard({required this.profile});

  final PersonalRecommendations? profile;

  /// Enough to show the shape of the taste, short of listing the library.
  static const int _maxChips = 4;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    if (data == null) return const SizedBox.shrink();

    final authors = data.favoriteAuthors.take(_maxChips).toList();
    final subjects = data.topSubjects.take(_maxChips).toList();
    final hasCount = data.scoredBooksCount > 0;
    if (!hasCount && authors.isEmpty && subjects.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCount)
              Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    size: 17,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'recommendations_basis_books',
                        params: {'count': data.scoredBooksCount.toString()},
                      ),
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            if (authors.isNotEmpty)
              _BasisRow(
                label: TranslationService.translate(
                  context,
                  'recommendations_basis_authors',
                ),
                values: authors,
                topPadding: hasCount ? 12 : 0,
              ),
            if (subjects.isNotEmpty)
              _BasisRow(
                label: TranslationService.translate(
                  context,
                  'recommendations_basis_subjects',
                ),
                values: subjects,
                topPadding: 10,
              ),
          ],
        ),
      ),
    );
  }
}

/// One labelled line of the basis card. The label and its values form a
/// single announcement: read separately, a bare list of names says nothing
/// about why it is there.
class _BasisRow extends StatelessWidget {
  const _BasisRow({
    required this.label,
    required this.values,
    required this.topPadding,
  });

  final String label;
  final List<String> values;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Semantics(
        label: '$label: ${values.join(', ')}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in values)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesign.radiusRound,
                      ),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      value,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reached with everything dismissed, or when the engine has nothing to
/// offer yet. Says which it is as far as it can, and what changes it,
/// instead of leaving the reader at a dead end.
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      // A ListView, not a Center: the empty state must still be pullable to
      // refresh, which is the one gesture that can bring the list back.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
          child: Column(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 44,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(context, 'recommendations_empty'),
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(
                  context,
                  'recommendations_empty_hint',
                ),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
