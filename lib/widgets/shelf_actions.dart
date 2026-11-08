import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../providers/sort_preference_provider.dart';
import '../services/shelf_rows.dart';
import '../services/translation_service.dart';
import '../utils/app_constants.dart';
import '../utils/shelf_name_rules.dart';
import 'app_snack_bar.dart';
import 'delete_shelf_dialog.dart';

/// The deletion waiting on its Undo and the Undo messages of a place where
/// shelves are changed, for as long as the reader stays there.
///
/// A deletion shows at once and its write waits. It goes when the message
/// closes (expired, dismissed, or replaced by another), when the reader leaves
/// or the app does, or when a second deletion starts. Undo writes nothing, so
/// nothing reaches a sync. Owned by whoever outlives the pages concerned: the
/// library screen for the shelf pages, which replace each other under it.
class ShelfActionsController extends ChangeNotifier
    with WidgetsBindingObserver {
  /// A live context to report a failed write in, when there is one.
  final BuildContext? Function() _context;

  /// Called once a deletion is written, even with no one left to show it.
  VoidCallback? onWritten;

  ShelfActionsController(this._context) {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _disposed = false;

  /// Shelves deleted whose write has not landed yet: the one waiting on its
  /// Undo, and any whose write is still on its way. By [Tag.stableKey].
  final Set<String> _hidden = {};

  /// The latest Undo of a move or a rename. It goes when the reader leaves:
  /// under a screen reader it would otherwise follow them everywhere.
  UndoableMessage? _undoMessage;

  _PendingShelfDeletion? _pending;

  /// Bumped by each listing: see [listingLanded].
  int _generation = 0;
  int get generation => _generation;

  /// Deletions the core has taken, by [Tag.stableKey], with the generation current
  /// when the write landed. Their rows stay hidden until a listing started
  /// after that lands: any earlier one may still hold the shelf.
  final Map<String, int> _written = {};

  /// The next change of page is the reader's own action carrying on, not a
  /// departure: see [willLand].
  bool _landing = false;

  /// [allTags] as the tree shows them: without the shelves hidden here, their
  /// sub-shelves where deleting them puts them.
  List<Tag> shown(List<Tag> allTags) => Tag.withoutShelves(allTags, {
    for (final t in allTags)
      if (_hidden.contains(t.stableKey)) t.id,
  });

  /// To call before reading the shelves; hand the result to [listingLanded].
  int beginListing() => ++_generation;

  /// A listing started at [generation] has landed.
  void listingLanded(int generation) {
    _written.removeWhere((key, writtenAt) {
      if (generation <= writtenAt) return false;
      _hidden.remove(key);
      return true;
    });
  }

  /// To call before a change of page that an Undo must survive.
  void willLand() => _landing = true;

  /// Whether the change of page just seen was announced by [willLand].
  bool consumeLanding() {
    final landing = _landing;
    _landing = false;
    return landing;
  }

  void keepUndo(UndoableMessage message) => _undoMessage = message;

  /// Hides [tag] at once and offers Undo; the write waits.
  void delete(BuildContext context, Tag tag, {required int subShelfCount}) {
    sendPending();
    final pending = _PendingShelfDeletion(
      tag,
      Provider.of<TagRepository>(context, listen: false),
      Provider.of<SortPreferenceProvider?>(context, listen: false),
    );
    _pending = pending;
    _hidden.add(tag.stableKey);
    notifyListeners();
    final message = AppSnackBar.undoable(
      context,
      deletedShelfMessage(context, tag, subShelfCount: subShelfCount),
      onUndo: () => _undo(pending),
    );
    pending.message = message;
    message.closed.then((reason) {
      if (reason != SnackBarClosedReason.action) _send(pending);
    });
  }

  void _undo(_PendingShelfDeletion pending) {
    if (!pending.settle()) return;
    if (identical(_pending, pending)) _pending = null;
    if (_disposed) return;
    _hidden.remove(pending.shelf.stableKey);
    notifyListeners();
  }

  /// Sends the deletion waiting on its Undo, if any, and takes the Undo off
  /// the screen: past this point it would undo nothing.
  void sendPending() {
    final pending = _pending;
    if (pending == null) return;
    _send(pending);
    pending.message?.dismiss();
  }

  /// A waiting deletion goes, and no Undo stays up behind.
  void leave() {
    sendPending();
    _undoMessage?.dismiss();
    _undoMessage = null;
  }

  void _send(_PendingShelfDeletion pending) {
    if (!pending.settle()) return;
    if (identical(_pending, pending)) _pending = null;
    unawaited(_write(pending));
  }

  /// The write itself. Started from `dispose` as well: nothing before its
  /// first await touches this state, nothing after it once disposed but
  /// telling [onWritten], so that what is still on screen catches up.
  Future<void> _write(_PendingShelfDeletion pending) async {
    final shelf = pending.shelf;
    try {
      // Row or not, the name has to leave the books: a shelf that only
      // exists in their subjects is deleted the same way (see deleteShelf).
      await pending.repo.deleteShelf(shelf);
      // The shelf's own order goes with it, only now that it is gone.
      await pending.sortPreference?.setShelfOrder(shelf.id, false);
    } catch (e) {
      debugPrint('Deleting a shelf failed: ${e.runtimeType}');
      if (_disposed) {
        // No one left to say it to, but what shows the shelves can read again.
        onWritten?.call();
        return;
      }
      _hidden.remove(shelf.stableKey);
      notifyListeners();
      final context = _context();
      if (context == null || !context.mounted) return;
      // Replacing the message of a deletion still waiting on its Undo
      // would send that one too: the error waits its turn.
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'error_generic'),
        queue: _pending != null,
      );
      return;
    }
    if (!_disposed) {
      _written[shelf.stableKey] = _generation;
      notifyListeners();
    }
    onWritten?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app sends a waiting deletion. Inactive is not leaving: a
    // glance at the control centre or a system dialog passes through it.
    // The Undo of a move or a rename stays: nothing waits behind it.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      sendPending();
    }
  }

  @override
  void dispose() {
    leave();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// A deletion shown but not written: it waits on its Undo. Holds what the
/// write needs, so that it can still go once the screen is gone.
class _PendingShelfDeletion {
  _PendingShelfDeletion(this.shelf, this.repo, this.sortPreference);

  final Tag shelf;
  final TagRepository repo;
  final SortPreferenceProvider? sortPreference;
  UndoableMessage? message;
  bool _settled = false;

  /// True the first time only: a deletion is sent, or undone, once.
  bool settle() {
    if (_settled) return false;
    _settled = true;
    return true;
  }
}

/// Asks for a new name for [tag], writes it and offers Undo.
///
/// [allTags] is the stored tree: the one shown moves the sub-shelves of a
/// deletion waiting on its Undo, and renaming leaves the shelf where it is.
void showRenameShelfDialog(
  BuildContext context, {
  required Tag tag,
  required List<Tag> allTags,
  required ValueChanged<String> onRenamed,
  required VoidCallback onUndone,
  required ValueSetter<UndoableMessage> onUndoShown,
}) {
  final controller = TextEditingController(text: tag.name);
  final formKey = GlobalKey<FormState>();

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(TranslationService.translate(dialogContext, 'edit_shelf')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    dialogContext,
                    'shelf_name',
                  ),
                  border: const OutlineInputBorder(),
                ),
                maxLength: maxShelfNameLength,
                // Counted, never cut: a longer name already there stays whole
                // while edited, and the validator says what to do.
                maxLengthEnforcement: MaxLengthEnforcement.none,
                validator: (value) => shelfNameError(
                  dialogContext,
                  value,
                  allTags,
                  renaming: tag,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(TranslationService.translate(dialogContext, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext);
                final name = controller.text.trim();
                // Nothing to write, and an Undo would undo nothing.
                if (name == tag.name) return;
                await _writeRename(
                  context,
                  tag,
                  name,
                  // Moving goes through "Move to…".
                  parentId: Tag.effectiveParentIds(allTags)[tag.id],
                  onRenamed: onRenamed,
                  onUndone: onUndone,
                  onUndoShown: onUndoShown,
                );
              }
            },
            child: Text(TranslationService.translate(dialogContext, 'update')),
          ),
        ],
      );
    },
  );
}

Future<void> _writeRename(
  BuildContext context,
  Tag tag,
  String name, {
  required String? parentId,
  required ValueChanged<String> onRenamed,
  required VoidCallback onUndone,
  required ValueSetter<UndoableMessage> onUndoShown,
}) async {
  try {
    final repo = Provider.of<TagRepository>(context, listen: false);
    // A name known only from the books has no row to rename yet.
    final row = await shelfWithRow(repo, tag) ?? tag;
    await repo.updateTag(row.uuid, name, parentId: parentId);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final taken = TranslationService.translate(
      context,
      'shelf_undo_name_taken',
    ).replaceAll('%s', tag.name);
    final failed = TranslationService.translate(context, 'error_update');
    onUndoShown(
      AppSnackBar.undoable(
        context,
        TranslationService.translate(context, 'shelf_updated'),
        onUndo: () => _undoRename(
          repo,
          messenger,
          row.id,
          tag.name,
          taken,
          failed,
          onUndone,
        ),
      ),
    );
    onRenamed(name);
  } catch (e) {
    debugPrint('Shelf actions: rename failed: $e');
    if (context.mounted) {
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'error_update'),
      );
    }
  }
}

/// Gives [previousName] back to the shelf [id], as Undo of a rename.
///
/// Read afresh: names are unique byte for byte, and one taken by another
/// shelf since stays with it; the rename then holds, and the reader is
/// told why. A move made meanwhile is kept. The messages are translated
/// beforehand: the context may be gone by the time Undo is tapped.
Future<void> _undoRename(
  TagRepository repo,
  ScaffoldMessengerState messenger,
  String id,
  String previousName,
  String takenMessage,
  String failedMessage,
  VoidCallback onUndone,
) async {
  try {
    final tags = await repo.getTags();
    final shelf = tags.where((t) => t.id == id).firstOrNull;
    if (shelf == null) {
      debugPrint('Shelf actions: undo found no shelf to rename');
      return;
    }
    if (tags.any((t) => t.id != id && t.name == previousName)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(takenMessage)));
      return;
    }
    await repo.updateTag(
      shelf.uuid,
      previousName,
      parentId: Tag.effectiveParentId(shelf, tags),
    );
  } catch (e) {
    debugPrint('Shelf actions: undo of a rename failed: ${e.runtimeType}');
    messenger
      ..hideCurrentSnackBar()
      // The theme's bar: its text is vetted on it, white on red is not.
      ..showSnackBar(SnackBar(content: Text(failedMessage)));
    return;
  }
  onUndone();
}

/// Creates a shelf at the first level, or inside [parent] when asked from a
/// shelf. [shownTags] is what the parent picker offers.
void showNewShelfDialog(
  BuildContext context, {
  Tag? parent,
  required List<Tag> shownTags,
  required VoidCallback onCreated,
}) {
  final outerContext = context;
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  // The list below knows its entries by instance, and a listing can hand out
  // new ones for the same shelf: a parent holding a shelf whose deletion waits
  // for its undo is one.
  Tag? selectedParent =
      shownTags.where((t) => t.id == parent?.id).firstOrNull ?? parent;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(TranslationService.translate(context, 'create_shelf')),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(
                        context,
                        'shelf_name',
                      ),
                      hintText: TranslationService.translate(
                        context,
                        'shelf_name_hint',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    maxLength: maxShelfNameLength,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    validator: (value) =>
                        shelfNameError(context, value, shownTags),
                  ),
                  // Only if hierarchical tags are enabled and shelves exist.
                  if (AppConstants.enableHierarchicalTags &&
                      shownTags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Tag?>(
                      value: selectedParent,
                      decoration: InputDecoration(
                        labelText: TranslationService.translate(
                          context,
                          'parent_shelf',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<Tag?>(
                          value: null,
                          child: Text(
                            TranslationService.translate(
                              context,
                              'first_level',
                            ),
                            // The theme's muted text, vetted on its dialogs
                            // and menus; a fixed grey was not, in the dark.
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        ...shownTags.map(
                          (tag) => DropdownMenuItem<Tag?>(
                            value: tag,
                            child: Text(tag.name),
                          ),
                        ),
                      ],
                      onChanged: (Tag? value) {
                        setDialogState(() {
                          selectedParent = value;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(TranslationService.translate(context, 'cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext);
                    await _writeNewShelf(
                      outerContext,
                      controller.text.trim(),
                      parent: selectedParent,
                      onCreated: onCreated,
                    );
                  }
                },
                child: Text(TranslationService.translate(context, 'create')),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _writeNewShelf(
  BuildContext context,
  String name, {
  required Tag? parent,
  required VoidCallback onCreated,
}) async {
  try {
    final repo = Provider.of<TagRepository>(context, listen: false);
    // A name known only from the books cannot parent another shelf yet.
    final parentRow = await shelfWithRow(repo, parent);
    await repo.createTag(name, parentId: parentRow?.id);
    if (!context.mounted) return;
    // Replaces an Undo still up rather than queueing behind it.
    AppSnackBar.success(
      context,
      TranslationService.translate(context, 'shelf_created'),
    );
    onCreated();
  } catch (e) {
    debugPrint('Shelf actions: creating a shelf failed: $e');
    if (context.mounted) {
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'tag_creation_error'),
      );
    }
  }
}
