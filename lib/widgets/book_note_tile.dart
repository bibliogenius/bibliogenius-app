import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/book_note.dart';
import '../services/translation_service.dart';

/// Asks the reader to confirm deleting a note. Every way of deleting a
/// note (swipe, action menu, screen reader action, edit dialog) goes through
/// this single confirmation.
Future<bool> confirmBookNoteDeletion(BuildContext context) async {
  final theme = Theme.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(TranslationService.translate(context, 'delete_note_confirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  return confirm == true;
}

/// "Delete" button for a note's edit dialog. Keyboard users cannot reach the
/// tile's long-press menu (keyboard activation is a tap, which opens the
/// editor), so the editor offers deletion too. On confirmation, closes the
/// edit dialog without saving, then calls [onDelete]; cancelling leaves the
/// edit dialog open.
class BookNoteDeleteAction extends StatelessWidget {
  final VoidCallback onDelete;

  const BookNoteDeleteAction({super.key, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: () async {
        if (!await confirmBookNoteDeletion(context)) return;
        if (!context.mounted) return;
        Navigator.pop(context, false);
        onDelete();
      },
      child: Text(TranslationService.translate(context, 'delete')),
    );
  }
}

enum _NoteAction { copy, delete }

/// Displays a single reading note.
/// Tap to edit, swipe left to delete, long-press or right-click for the
/// action menu (copy, delete).
///
/// Deletion does not rely on the swipe alone: nothing on screen announces
/// it, and on desktop a trackpad scroll does not trigger it.
///
/// Copying goes through a long-press menu rather than selectable text:
/// SelectableText and SelectionArea both claim the horizontal touch drag,
/// which took swipe-to-delete away from the text (most of the card). To copy
/// a passage only, the edit dialog's text field already allows selection.
class BookNoteTile extends StatelessWidget {
  final BookNote note;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BookNoteTile({
    super.key,
    required this.note,
    this.onEdit,
    this.onDelete,
  });

  String _formatRelativeDate(BuildContext context, DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _copyNote(BuildContext context) async {
    final confirmation = TranslationService.translate(context, 'note_copied');
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: note.content));
    messenger?.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _deleteNote(BuildContext context) async {
    if (await confirmBookNoteDeletion(context)) onDelete!();
  }

  Future<void> _showActions(BuildContext context) async {
    final copyLabel = TranslationService.translate(context, 'note_copy_action');
    final deleteLabel = TranslationService.translate(context, 'delete');
    final action = await showModalBottomSheet<_NoteAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(copyLabel),
              onTap: () => Navigator.pop(ctx, _NoteAction.copy),
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(deleteLabel),
                onTap: () => Navigator.pop(ctx, _NoteAction.delete),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _NoteAction.copy:
        await _copyNote(context);
      case _NoteAction.delete:
        await _deleteNote(context);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copyLabel = TranslationService.translate(context, 'note_copy_action');
    final deleteLabel = TranslationService.translate(context, 'delete');

    Widget card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onEdit,
          onLongPress: () => _showActions(context),
          onSecondaryTap: () => _showActions(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.content, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (note.page != null) ...[
                      Icon(
                        Icons.bookmark_outline,
                        size: 14,
                        color: theme.colorScheme.onSurface.withAlpha(128),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'p. ${note.page}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(128),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      _formatRelativeDate(context, note.createdDateTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onDelete != null) {
      card = Dismissible(
        key: ValueKey(note.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => confirmBookNoteDeletion(context),
        onDismissed: (_) => onDelete!(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: card,
      );
    }

    // One merged node: the focused tile offers tap, long press (with its
    // hint) and direct copy and delete actions (VoiceOver rotor, TalkBack
    // actions menu). The note text comes from the Text below, read once.
    // The Dismissible only adds unnamed scroll actions, so Delete is
    // announced once.
    return MergeSemantics(
      child: Semantics(
        onLongPressHint: copyLabel,
        customSemanticsActions: {
          CustomSemanticsAction(label: copyLabel): () => _copyNote(context),
          if (onDelete != null)
            CustomSemanticsAction(label: deleteLabel): () =>
                _deleteNote(context),
        },
        child: card,
      ),
    );
  }
}
