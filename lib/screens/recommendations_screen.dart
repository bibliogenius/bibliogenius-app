import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/recommendation_display.dart';
import '../widgets/external_suggestion_sheet.dart';
import '../widgets/suggestion_tile.dart';

/// "See all" for the personal suggestions (ADR-059 follow-up): the full
/// ranked list the dashboard digest truncates, reusing the same
/// [RecommendationProvider] cache and the same tiles, including the
/// "Not interested" dismissal with its SnackBar Undo. External discovery
/// cards (ADR-060) append after the locals, capped at 10, with the same
/// badge, dismissal and pre-import tap flow as the dashboard.
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<RecommendationProvider>();
      await provider.loadPersonal();
      if (!mounted) return;
      await provider.loadExternal(
        langs: context.read<ThemeProvider>().userLanguages,
      );
    });
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

    final dismissTooltip = TranslationService.translate(
      context,
      'recommendation_not_interested',
    );

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'recommendations_personal'),
          ),
        ),
      ),
      body: suggestions.isEmpty
          // Reached with everything dismissed (or after a catalogue change
          // emptied the list): say so instead of a blank page.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  TranslationService.translate(
                    context,
                    'recommendations_empty',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SuggestionSeparator(),
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                final bookId = suggestion.book.id;
                final externalKey = suggestion.externalKey;
                return SuggestionTile(
                  suggestion: suggestion,
                  onTap: suggestion.isExternal
                      ? () => ExternalSuggestionSheet.show(context, suggestion)
                      : null,
                  onDismiss: externalKey != null
                      ? () => dismissExternalSuggestionWithUndo(
                          context,
                          externalKey,
                        )
                      : bookId == null
                      ? null
                      : () => dismissRecommendationWithUndo(context, bookId),
                  dismissTooltip: dismissTooltip,
                );
              },
            ),
    );
  }
}
