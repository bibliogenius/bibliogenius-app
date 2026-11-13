import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/book_note.dart';
import '../services/translation_service.dart';

/// Displays a single reading note.
/// Tap to edit, swipe left to delete, long-press to copy.
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

  Future<void> _showActions(BuildContext context) async {
    final copyLabel = TranslationService.translate(context, 'note_copy_action');
    final copy = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.copy),
          title: Text(copyLabel),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (copy == true && context.mounted) await _copyNote(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copyLabel = TranslationService.translate(context, 'note_copy_action');

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
        confirmDismiss: (_) async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                TranslationService.translate(context, 'delete_note_confirm'),
              ),
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
        },
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
    // hint) and a direct copy action (VoiceOver rotor, TalkBack actions
    // menu). The note text comes from the Text below, read once.
    return MergeSemantics(
      child: Semantics(
        onLongPressHint: copyLabel,
        customSemanticsActions: {
          CustomSemanticsAction(label: copyLabel): () => _copyNote(context),
        },
        child: card,
      ),
    );
  }
}
