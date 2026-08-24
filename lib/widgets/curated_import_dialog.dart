import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/collection_import_service.dart';
import '../services/curated_affinity_service.dart';
import '../services/curated_lists_service.dart';
import '../services/external_suggestion_dismissal_service.dart';
import '../services/genre_tag_service.dart';
import '../services/translation_service.dart';
import '../utils/book_genres.dart';
import '../utils/curated_tag_genre_aliases.dart';
import '../utils/language_constants.dart';
import 'curated_book_preview.dart';
import 'import_progress_dialog.dart';

/// What the reader chose in the pre-import dialog.
class CuratedImportChoice {
  const CuratedImportChoice({required this.status, required this.shelve});

  /// `owned` (no reading status), `to_read` or `wanting`.
  final String status;

  /// Whether the imported books are filed under their matching genre
  /// shelves (ADR-066 section 6).
  final bool shelve;
}

/// The pre-import dialog for a curated list, and the import it launches.
///
/// Promoted out of `ImportCuratedListScreen` so the list-suggestion card
/// (ADR-066) opens the REAL flow rather than a copy of it: the status
/// choice, the ISBN dedup and the shelving option all live here, and both
/// entry points get every one of them.
abstract final class CuratedImportDialog {
  /// Ask, then import. Returns the number of books imported, or null when
  /// the reader cancelled.
  ///
  /// The caller owns what happens next (a screen pops, a card disappears);
  /// this owns the dialog, the import and its feedback.
  static Future<int?> show(BuildContext context, CuratedList list) async {
    final theme = context.read<ThemeProvider>();
    final languages = resolveReaderLanguages(
      Localizations.localeOf(context).languageCode,
      theme.userLanguages,
    );
    final locale = Localizations.localeOf(context).languageCode;

    // Resolved BEFORE the dialog opens: the option must be absent when
    // nothing resolves rather than present and inert (no dead option), and
    // the labels are named on it so opting in is an informed tap.
    final shelfLabels = await resolveShelfLabels(context, list);
    if (!context.mounted) return null;

    final ownedIndexes = await resolveOwnedEntries(context, list);
    if (!context.mounted) return null;

    final choice = await _ask(context, list, locale, shelfLabels, ownedIndexes);
    if (choice == null || !context.mounted) return null;

    return _import(
      context,
      list: list,
      languages: languages,
      locale: locale,
      choice: choice,
      shelfLabels: shelfLabels,
    );
  }

  /// Genre shelf labels this list resolves to, in the reader's own spelling
  /// and language.
  ///
  /// Step 1 of ADR-066 section 6 reuses an EXISTING shelf wherever the
  /// reader already keeps one, whatever language they typed it in, because
  /// `genreAliases` knows every translation of a genre key. Step 2 supplies
  /// the closed-list label for the genres they have no shelf for yet, which
  /// is what makes the option exist at all on a library with few shelves.
  ///
  /// Never a favorites-like label: the values come from the closed genre
  /// vocabulary, which contains none (ADR-059 poisoning rule).
  static Future<List<String>> resolveShelfLabels(
    BuildContext context,
    CuratedList list,
  ) async {
    final keys = genreKeysForTags(list.tags);
    if (keys.isEmpty) return const [];

    List<String> existing = const [];
    try {
      final tags = await context.read<TagRepository>().getTags();
      existing = tags.map((t) => t.name).toList();
    } catch (_) {
      // No shelves readable: step 2 still resolves, so the option survives.
    }
    if (!context.mounted) return const [];

    final labels = <String>[];
    for (final genre in allBookGenres) {
      if (!keys.contains(genre.key)) continue;
      final aliases = genreAliases(genre.key);
      final owned = existing.where(
        (name) => aliases.contains(name.trim().toLowerCase()),
      );
      // The reader's own spelling wins over ours whenever they have one.
      labels.add(owned.isNotEmpty ? owned.first : genreLabel(context, genre));
    }
    return labels;
  }

  /// Which entries the reader already has, for the preview to mark.
  ///
  /// Reuses the tier's own membrane through [CuratedAffinityService], never
  /// a second definition of "owned": a card claiming three books in common
  /// while the preview ticks two would be worse than no mark at all.
  ///
  /// Best effort, and silent when it cannot answer. The inputs are memoised
  /// on the provider, so this is free once the affinity has run; a library
  /// below the ADR-059 profile floor, or an entry point with no provider
  /// above it, marks nothing rather than holding the dialog shut.
  static Future<Set<int>> resolveOwnedEntries(
    BuildContext context,
    CuratedList list,
  ) async {
    try {
      final inputs = await context
          .read<RecommendationProvider>()
          .ensureLookupInputs();
      if (inputs == null) return const {};
      return const CuratedAffinityService().ownedEntryIndexes(
        list: list,
        inputs: inputs,
      );
    } catch (_) {
      return const {};
    }
  }

  static Future<CuratedImportChoice?> _ask(
    BuildContext context,
    CuratedList list,
    String locale,
    List<String> shelfLabels,
    Set<int> ownedIndexes,
  ) {
    var status = 'wanting'; // Wishlist, the safest default.
    // Off by default: filing books onto shelves is a mutation the reader
    // did not ask for, and the app does not decide for them. The labels
    // sit next to the switch, so saying yes is one tap.
    var shelve = false;

    return showDialog<CuratedImportChoice?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Text(
                TranslationService.translate(
                  dialogContext,
                  'import_list_title',
                  params: {'title': list.getTitle(locale)},
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(
                        dialogContext,
                        'import_list_desc',
                        params: {'count': list.books.length.toString()},
                      ),
                    ),
                    const SizedBox(height: 12),
                    // What the reader is about to add, before they are asked
                    // to agree to it. First, because a count is not an
                    // answer to "do I want these books", and because the
                    // suggestion card of ADR-066 reaches this dialog without
                    // the reader having gone looking for the list.
                    //
                    // Bounded when unfolded: a 72-volume list would push the
                    // status choice and the buttons off the screen, and the
                    // dialog would become a wall of titles with nothing to
                    // act on.
                    CuratedBookPreview(
                      books: list.books,
                      maxExpandedHeight: 220,
                      ownedIndexes: ownedIndexes,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      TranslationService.translate(
                        dialogContext,
                        'imported_books_status',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        _statusItem(
                          dialogContext,
                          'owned',
                          Icons.remove_circle_outline,
                          'no_reading_status',
                        ),
                        _statusItem(
                          dialogContext,
                          'to_read',
                          Icons.bookmark_border,
                          'to_read_status',
                        ),
                        _statusItem(
                          dialogContext,
                          'wanting',
                          Icons.favorite_border,
                          'wishlist_status',
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => status = val ?? 'owned'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status == 'wanting'
                          ? TranslationService.translate(
                              dialogContext,
                              'books_added_to_wishlist',
                            )
                          : TranslationService.translate(
                              dialogContext,
                              'copies_created_automatically',
                            ),
                      style: Theme.of(
                        dialogContext,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    // Absent when nothing resolves: an option that could do
                    // nothing is worse than no option.
                    if (shelfLabels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: shelve,
                        onChanged: (v) => setState(() => shelve = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          TranslationService.translate(
                            dialogContext,
                            'curated_import_shelve_option',
                          ),
                        ),
                        subtitle: Text(
                          TranslationService.translate(
                            dialogContext,
                            'curated_import_shelve_option_detail',
                            params: {'labels': shelfLabels.join(', ')},
                          ),
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: Text(
                    TranslationService.translate(dialogContext, 'cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    CuratedImportChoice(status: status, shelve: shelve),
                  ),
                  child: Text(
                    TranslationService.translate(dialogContext, 'import'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static DropdownMenuItem<String> _statusItem(
    BuildContext context,
    String value,
    IconData icon,
    String labelKey,
  ) {
    return DropdownMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(TranslationService.translate(context, labelKey)),
        ],
      ),
    );
  }

  static Future<int?> _import(
    BuildContext context, {
    required CuratedList list,
    required List<String> languages,
    required String locale,
    required CuratedImportChoice choice,
    required List<String> shelfLabels,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final listTitle = list.getTitle(locale);
    final apiService = context.read<ApiService>();
    final recommendations = context.read<RecommendationProvider>();
    final bookRefresh = context.read<BookRefreshNotifier>();

    // Shelf rows are created ONCE, before the loop, and only when asked.
    // Best effort throughout: a shelf that cannot be created must never
    // cost the reader their books.
    var subjects = const <String>[];
    if (choice.shelve && shelfLabels.isNotEmpty) {
      subjects = await _ensureShelves(context, list);
    }

    // Behind a progress modal, because this is one network lookup PER BOOK
    // in sequence: without it the reader taps Import, the dialog closes, and
    // the screen says nothing for as long as the slowest chain takes. The
    // modal also gives them the way out they did not have.
    if (!context.mounted) return null;
    final result = await ImportProgressDialog.run<CollectionImportResult>(
      context,
      total: list.books.length,
      task: (onProgress, isCancelled) =>
          CollectionImportService(apiService).importList(
            list: list,
            langCode: locale,
            readerLanguages: languages,
            readingStatus: choice.status == 'owned' ? '' : choice.status,
            shouldMarkAsOwned: choice.status != 'wanting',
            subjects: subjects,
            onProgress: onProgress,
            isCancelled: isCancelled,
          ),
    );
    // Null only when the task threw and the modal came down on its own.
    if (result == null) return null;

    // Importing is the strongest signal a reader can give that they have
    // dealt with a list, so it stops being SUGGESTED (ADR-066 section 7).
    // A partial import would otherwise come back with a higher overlap
    // ratio and be pushed harder, which is the perverse outcome. The list
    // itself stays in the import catalogue, which never reads this store.
    if (!result.hasError || result.successCount > 0) {
      await ExternalSuggestionDismissalService.dismiss('list:${list.id}');
      recommendations.hideCuratedAfterImport(list.id);
      // A collection and up to a hundred books just appeared, and nothing on
      // screen knows. The Collections page and the library both listen to
      // this; without it the reader lands back on a list that does not
      // contain what they just imported and has to leave the page and come
      // back for it to show up.
      bookRefresh.refresh();
    }

    if (!context.mounted) return result.successCount;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.hasError && result.successCount == 0
              ? '${TranslationService.translate(context, 'error')}: ${result.error ?? ''}'
              : TranslationService.translate(
                  context,
                  'collection_created',
                  params: {
                    'title': listTitle,
                    'count': result.successCount.toString(),
                  },
                ),
        ),
        backgroundColor: result.successCount == 0
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
    return result.successCount;
  }

  /// Create (or find) the genre shelves and return their labels.
  ///
  /// `resolveShelfChain` already reuses an existing shelf by name wherever
  /// it stands and never re-parents it, so step 1 and step 2 are the same
  /// call: the reader's own "Polar" is adopted, and a genre they have no
  /// shelf for gets one created under "Genre".
  static Future<List<String>> _ensureShelves(
    BuildContext context,
    CuratedList list,
  ) async {
    final keys = genreKeysForTags(list.tags);
    if (keys.isEmpty) return const [];
    final service = GenreTagService(context.read<TagRepository>());
    final rootLabel = TranslationService.translate(context, genreRootKey);

    final labels = <String>[];
    for (final genre in allBookGenres) {
      if (!keys.contains(genre.key)) continue;
      final parent = parentOfGenre(genre);
      if (!context.mounted) break;
      final chain = [
        rootLabel,
        if (parent != null) genreLabel(context, parent),
        genreLabel(context, genre),
      ];
      try {
        final shelf = await service.resolveShelfChain(chain);
        if (!labels.contains(shelf.name)) labels.add(shelf.name);
      } catch (e) {
        // Best effort: a shelf that fails to resolve is dropped, the
        // import proceeds, and the reader keeps the books either way.
        debugPrint('Curated import shelving failed for ${genre.key}: $e');
      }
    }
    return labels;
  }
}
