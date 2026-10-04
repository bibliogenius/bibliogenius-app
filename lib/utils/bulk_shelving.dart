import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/collection_repository.dart';
import '../models/collection.dart';
import '../providers/book_refresh_notifier.dart';
import '../services/translation_service.dart';
import '../widgets/collection_selector.dart';
import '../widgets/hierarchical_tag_selector.dart';

/// Where a selection of books was made, when that place is a single shelf or
/// collection: the flow then offers to remove the books from it, which turns
/// "add to" into "move to".
class BulkShelvingSource {
  /// Name shown in the "remove from" option.
  final String label;

  /// Shelf paths to strip from the books' subjects. A shelf is stored under
  /// its full path, and under its bare name on books filed before shelves
  /// became hierarchical: both spellings go.
  final List<String> shelfPaths;

  final String? collectionId;

  const BulkShelvingSource.shelf({
    required this.label,
    required this.shelfPaths,
  }) : collectionId = null;

  const BulkShelvingSource.collection({
    required this.label,
    required String this.collectionId,
  }) : shelfPaths = const [];
}

class _BulkShelvingChoice {
  final List<String> shelves;
  final List<Collection> collections;
  final bool removeFromSource;

  const _BulkShelvingChoice({
    required this.shelves,
    required this.collections,
    required this.removeFromSource,
  });
}

/// Ask where to file [bookIds] (shelves and/or collections), apply it in one
/// atomic call, and report the outcome in a snackbar.
///
/// Returns true when the books were filed, false when the user cancelled or
/// the call failed. Adding is the default; removal from [source] is opt-in.
Future<bool> showBulkShelvingFlow(
  BuildContext context, {
  required List<String> bookIds,
  BulkShelvingSource? source,
}) async {
  if (bookIds.isEmpty) return false;

  final choice = await showModalBottomSheet<_BulkShelvingChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BulkShelvingSheet(count: bookIds.length, source: source),
  );
  if (choice == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final remove = choice.removeFromSource ? source : null;
  try {
    final changed = await context.read<CollectionRepository>().assignBooks(
      bookIds: bookIds,
      addShelves: choice.shelves,
      addCollectionIds: choice.collections.map((c) => c.id).toList(),
      removeShelves: remove?.shelfPaths ?? const [],
      removeCollectionIds: [
        if (remove?.collectionId != null) remove!.collectionId!,
      ],
    );
    if (!context.mounted) return true;
    // Shelf counts, collection stacks and the favorites cache all read from
    // what just changed.
    context.read<BookRefreshNotifier>().refresh();
    final key = changed == 0
        ? 'bulk_assign_nothing_changed'
        : (changed == 1 ? 'bulk_assign_done' : 'bulk_assign_done_plural');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(
            context,
            key,
          ).replaceAll('{count}', '$changed'),
        ),
      ),
    );
    return true;
  } catch (e) {
    debugPrint('Bulk shelving failed: $e');
    if (!context.mounted) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'error_save_failed'),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return false;
  }
}

class _BulkShelvingSheet extends StatefulWidget {
  final int count;
  final BulkShelvingSource? source;

  const _BulkShelvingSheet({required this.count, this.source});

  @override
  State<_BulkShelvingSheet> createState() => _BulkShelvingSheetState();
}

class _BulkShelvingSheetState extends State<_BulkShelvingSheet> {
  List<String> _shelves = [];
  List<Collection> _collections = [];
  bool _removeFromSource = false;

  bool get _hasDestination => _shelves.isNotEmpty || _collections.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final title = TranslationService.translate(
      context,
      widget.count == 1 ? 'bulk_assign_title' : 'bulk_assign_title_plural',
    ).replaceAll('{count}', '${widget.count}');

    return Padding(
      // The collection field opens the keyboard; keep it and the confirm
      // button above it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 20),
            HierarchicalTagSelector(
              selectedTags: _shelves,
              onTagsChanged: (shelves) =>
                  setState(() => _shelves = List.of(shelves)),
            ),
            const SizedBox(height: 16),
            CollectionSelector(
              selectedCollections: _collections,
              onChanged: (collections) =>
                  setState(() => _collections = List.of(collections)),
            ),
            if (source != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _removeFromSource,
                onChanged: (value) =>
                    setState(() => _removeFromSource = value ?? false),
                title: Text(
                  TranslationService.translate(
                    context,
                    'bulk_assign_remove_from',
                  ).replaceAll('{name}', source.label),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(TranslationService.translate(context, 'cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('bulkAssignConfirmButton'),
                  onPressed: _hasDestination
                      ? () => Navigator.pop(
                          context,
                          _BulkShelvingChoice(
                            shelves: _shelves,
                            collections: _collections,
                            removeFromSource: _removeFromSource,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    TranslationService.translate(
                      context,
                      _removeFromSource
                          ? 'bulk_assign_confirm_move'
                          : 'bulk_assign_confirm',
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
