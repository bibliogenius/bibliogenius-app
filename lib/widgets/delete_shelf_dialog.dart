import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';

/// The one rule of deleting a shelf, whichever screen it starts from: the
/// books stay in the library and the sub-shelves move up one level, under
/// the deleted shelf's parent. The sub-shelves are only mentioned when there
/// are some.
List<String> deleteShelfRule(
  BuildContext context, {
  required int subShelfCount,
}) => [
  TranslationService.translate(context, 'delete_shelf_books_kept'),
  if (subShelfCount > 0)
    TranslationService.translate(
      context,
      subShelfCount == 1
          ? 'delete_shelf_children_moved_up'
          : 'delete_shelf_children_moved_up_plural',
    ).replaceAll('%d', '$subShelfCount'),
];

/// The text of the shelf deletion confirmation: the question, then the rule.
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
    ...deleteShelfRule(context, subShelfCount: subShelfCount),
  ];
  return parts.join('\n\n');
}

/// What the shelves tab says once [tag] is gone, Undo next to it: the same
/// rule as the confirmation, word for word.
String deletedShelfMessage(
  BuildContext context,
  Tag tag, {
  required int subShelfCount,
}) {
  final sentences = [
    TranslationService.translate(
      context,
      'shelf_deleted_named',
    ).replaceAll('%s', tag.name),
    ...deleteShelfRule(context, subShelfCount: subShelfCount),
  ];
  // Japanese and Chinese close a sentence with 。 and put no space after.
  final gap = sentences.first.endsWith('。') ? '' : ' ';
  return sentences.join(gap);
}

/// Ask before deleting [tag]. Resolves to true only when the reader confirms.
///
/// The management screen's way to delete. The shelves tab deletes at once
/// and offers Undo instead (see [deletedShelfMessage]).
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
