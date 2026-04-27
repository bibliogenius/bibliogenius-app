import 'package:flutter/material.dart';

import '../../data/repositories/collection_repository.dart';
import '../../models/collection_deletion_preview.dart';
import '../../services/translation_service.dart';

/// Outcome of the "delete collection" confirmation dialog.
enum CollectionDeleteOutcome {
  /// User cancelled.
  cancelled,

  /// User confirmed; delete the collection only (books remain orphaned).
  collectionOnly,

  /// User confirmed with the checkbox ticked; delete the collection AND
  /// its eligible books (non-loaned, not in another collection, not on a
  /// shelf). Ineligible books stay in the library.
  withBooks,
}

/// Show the collection deletion confirmation dialog, pre-loading the
/// deletion preview so the "also delete books" checkbox can display live
/// impact counts.
///
/// Used from both the collection list (long-press) and the collection
/// detail screen (quick actions) so the UX stays identical.
Future<CollectionDeleteOutcome> confirmCollectionDeletion(
  BuildContext context,
  CollectionRepository repo,
  String collectionId,
) async {
  // Best-effort preview: if it fails we fall back to a plain confirm
  // dialog (no checkbox) rather than blocking deletion altogether.
  CollectionDeletionPreview? preview;
  try {
    preview = await repo.getDeletionPreview(collectionId);
  } catch (_) {
    preview = null;
  }
  if (!context.mounted) return CollectionDeleteOutcome.cancelled;

  final canOfferBookDelete = preview != null && preview.totalBooks > 0;
  bool deleteBooks = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              TranslationService.translate(context, 'delete_collection_title'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(
                    context,
                    'delete_collection_warning',
                  ),
                ),
                if (canOfferBookDelete) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: deleteBooks,
                    onChanged: (v) =>
                        setDialogState(() => deleteBooks = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      TranslationService.translate(
                        context,
                        'delete_collection_include_books',
                      ),
                    ),
                  ),
                  if (deleteBooks) _DeletionPreviewSummary(preview: preview!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(TranslationService.translate(context, 'cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(TranslationService.translate(context, 'delete')),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return CollectionDeleteOutcome.cancelled;
  return deleteBooks
      ? CollectionDeleteOutcome.withBooks
      : CollectionDeleteOutcome.collectionOnly;
}

/// Summary + legend shown under the "also delete books" checkbox.
class _DeletionPreviewSummary extends StatelessWidget {
  final CollectionDeletionPreview preview;

  const _DeletionPreviewSummary({required this.preview});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyMedium;
    final small = Theme.of(context).textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.only(left: 48, right: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(
              context,
              'delete_collection_preview_summary',
              params: {
                'to_delete': preview.toDelete.toString(),
                'to_keep': preview.toKeep.toString(),
              },
            ),
            style: body?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            TranslationService.translate(
              context,
              'delete_collection_preview_legend',
            ),
            style: small?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
