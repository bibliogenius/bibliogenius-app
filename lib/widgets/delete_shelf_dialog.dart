import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';

/// The text of the shelf deletion confirmation. Deleting a shelf has one rule
/// whichever screen it starts from: the books stay in the library and the
/// sub-shelves move up one level, under the deleted shelf's parent.
String deleteShelfMessage(
  BuildContext context,
  Tag tag, {
  required int subShelfCount,
}) {
  final parts = [
    TranslationService.translate(
      context,
      'delete_shelf_confirm',
    ).replaceAll('%s', tag.name),
    TranslationService.translate(context, 'delete_shelf_books_kept'),
    if (subShelfCount > 0)
      TranslationService.translate(
        context,
        subShelfCount == 1
            ? 'delete_shelf_children_moved_up'
            : 'delete_shelf_children_moved_up_plural',
      ).replaceAll('%d', '$subShelfCount'),
  ];
  return parts.join('\n\n');
}

/// Ask before deleting [tag]. Resolves to true only when the reader confirms.
///
/// The confirmation stays until deleting can be undone; it is the same dialog
/// from the shelves tab and from the management screen.
Future<bool> confirmDeleteShelf(
  BuildContext context,
  Tag tag, {
  required int subShelfCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(
          TranslationService.translate(dialogContext, 'delete_shelf'),
        ),
        content: Text(
          deleteShelfMessage(dialogContext, tag, subShelfCount: subShelfCount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(TranslationService.translate(dialogContext, 'cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(TranslationService.translate(dialogContext, 'delete')),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
