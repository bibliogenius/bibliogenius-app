import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/shelf_rows.dart';
import '../services/translation_service.dart';
import 'app_snack_bar.dart';
import 'shelf_placement_tree.dart';

/// What a move needs to be taken back: where the shelf showed before it,
/// and who to tell once it is there again.
class ShelfMoveUndo {
  /// The parent the tree showed the shelf under, null for the first level.
  final String? previousParentId;

  /// Called once the shelf is back, to reload what shows it.
  final VoidCallback onUndone;

  /// Handed the Undo message, so the screen can take it down on leaving.
  final ValueSetter<UndoableMessage>? onShown;

  const ShelfMoveUndo({
    required this.previousParentId,
    required this.onUndone,
    this.onShown,
  });
}

/// Where the reader chose to move a shelf. Wraps the parent so that the
/// first level (a null parent) cannot be mistaken for a dismissed sheet.
class _Destination {
  final Tag? parent;

  const _Destination(this.parent);
}

/// Moves [shelf] to the place the reader taps in the shelf tree, then says
/// where it went. Resolves to true once the shelf has moved.
///
/// The one way to move a shelf, from the shelves tab and from the
/// management screen alike, so both send the same update and say the same
/// thing. The tree greys out the shelf's own branch and marks where it sits
/// now; a tap is the choice, with no confirm button that could send the
/// shelf to the first level unasked. With [onUndone], the message offers
/// Undo, which puts the shelf back where the tree showed it.
Future<bool> showMoveShelfSheet(
  BuildContext context, {
  required Tag shelf,
  required List<Tag> allTags,
  VoidCallback? onUndone,
  ValueSetter<UndoableMessage>? onUndoShown,
}) async {
  final destination = await showModalBottomSheet<_Destination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      key: const Key('moveShelfSheet'),
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, _) => ShelfPlacementTree(
        allTags: allTags,
        title: TranslationService.translate(
          sheetContext,
          'move_shelf_to_title',
        ).replaceAll('{name}', shelf.name),
        subtitle: TranslationService.translate(
          sheetContext,
          'move_shelf_to_subtitle',
        ),
        firstLevelLabel: TranslationService.translate(
          sheetContext,
          'move_shelf_to_first_level',
        ),
        disabledBranchRootId: shelf.id,
        // Where the tree shows the shelf: a parent lost to sync reads as the
        // first level there, so it is the first level that is marked.
        currentParentId: Tag.effectiveParentId(shelf, allTags),
        markCurrentPlace: true,
        onPlace: (parent) =>
            Navigator.of(sheetContext).pop(_Destination(parent)),
      ),
    ),
  );
  if (destination == null || !context.mounted) return false;
  return moveShelf(
    context,
    shelf: shelf,
    parent: destination.parent,
    undo: onUndone == null
        ? null
        : ShelfMoveUndo(
            previousParentId: Tag.effectiveParentId(shelf, allTags),
            onUndone: onUndone,
            onShown: onUndoShown,
          ),
  );
}

/// Files [shelf] under [parent] (the first level when null), then says
/// where it went. Resolves to true once the shelf has moved.
///
/// The one write behind every way of moving a shelf, the tree sheet and a
/// drop in the shelves tab alike, so both send the same update and show the
/// same message. With [undo], the message offers Undo.
Future<bool> moveShelf(
  BuildContext context, {
  required Tag shelf,
  required Tag? parent,
  ShelfMoveUndo? undo,
}) async {
  final repo = Provider.of<TagRepository>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  // Translated now: the context may be gone once the write or Undo fails.
  final failed = TranslationService.translate(context, 'error_update');
  final String movedId;
  try {
    final parentId = (await shelfWithRow(repo, parent))?.id;
    if (shelf.isPersisted) {
      await repo.updateTag(shelf.uuid, shelf.name, parentId: parentId);
      movedId = shelf.id;
    } else {
      // A name known only from the books' subjects has no row to update:
      // giving it one, at the chosen place, is what moves it.
      movedId = (await repo.createTag(shelf.name, parentId: parentId)).id;
    }
  } catch (e) {
    // The core refuses a move under the shelf's own branch; neither the
    // sheet nor a drop offers one, but a sync can change the tree meanwhile.
    debugPrint('Move shelf: update failed: $e');
    // Replaces an Undo still up rather than queueing behind it.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failed)));
    return false;
  }
  if (!context.mounted) return true;

  final message = parent == null
      ? TranslationService.translate(context, 'shelf_moved_to_first_level')
      : TranslationService.translate(
          context,
          'shelf_moved_under',
        ).replaceAll('{parent}', parent.name);
  final text = message.replaceAll('{name}', shelf.name);
  if (undo == null) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
  } else {
    final shown = AppSnackBar.undoable(
      context,
      text,
      onUndo: () => _undoMove(repo, messenger, movedId, undo, failed),
    );
    undo.onShown?.call(shown);
  }
  return true;
}

/// Puts the shelf [movedId] back under the parent the tree showed before.
///
/// Read afresh: a sync may have renamed the shelf, or removed its former
/// parent, while the message was up. A rename is kept; a parent gone (or
/// one with no row) leaves the first level, where the tree shows a shelf
/// whose parent is missing. A shelf that got its row from the move keeps
/// it: deleting the row would take the name off its books. A failure shows
/// [failedMessage].
Future<void> _undoMove(
  TagRepository repo,
  ScaffoldMessengerState messenger,
  String movedId,
  ShelfMoveUndo undo,
  String failedMessage,
) async {
  try {
    final tags = await repo.getTags();
    final moved = tags.where((t) => t.id == movedId).firstOrNull;
    if (moved == null) {
      debugPrint('Move shelf: undo found no shelf to put back');
      return;
    }
    final former = undo.previousParentId;
    final parentId =
        former != null && tags.any((t) => t.id == former && t.isPersisted)
        ? former
        : null;
    await repo.updateTag(moved.uuid, moved.name, parentId: parentId);
  } catch (e) {
    // The core refuses a parent that has become one of the shelf's own
    // sub-shelves meanwhile.
    debugPrint('Move shelf: undo failed: $e');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failedMessage)));
    return;
  }
  undo.onUndone();
}
