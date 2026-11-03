import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/shelf_rows.dart';
import '../services/translation_service.dart';
import 'shelf_placement_tree.dart';

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
/// shelf to the first level unasked.
Future<bool> showMoveShelfSheet(
  BuildContext context, {
  required Tag shelf,
  required List<Tag> allTags,
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
  return moveShelf(context, shelf: shelf, parent: destination.parent);
}

/// Files [shelf] under [parent] (the first level when null), then says
/// where it went. Resolves to true once the shelf has moved.
///
/// The one write behind every way of moving a shelf, the tree sheet and a
/// drop in the shelves tab alike, so both send the same update and show the
/// same message.
Future<bool> moveShelf(
  BuildContext context, {
  required Tag shelf,
  required Tag? parent,
}) async {
  final repo = Provider.of<TagRepository>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final parentId = (await shelfWithRow(repo, parent))?.id;
    if (shelf.isPersisted) {
      await repo.updateTag(shelf.uuid, shelf.name, parentId: parentId);
    } else {
      // A name known only from the books' subjects has no row to update:
      // giving it one, at the chosen place, is what moves it.
      await repo.createTag(shelf.name, parentId: parentId);
    }
  } catch (e) {
    // The core refuses a move under the shelf's own branch; neither the
    // sheet nor a drop offers one, but a sync can change the tree meanwhile.
    debugPrint('Move shelf: update failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
  if (!context.mounted) return true;

  final message = parent == null
      ? TranslationService.translate(context, 'shelf_moved_to_first_level')
      : TranslationService.translate(
          context,
          'shelf_moved_under',
        ).replaceAll('{parent}', parent.name);
  messenger.showSnackBar(
    SnackBar(content: Text(message.replaceAll('{name}', shelf.name))),
  );
  return true;
}
