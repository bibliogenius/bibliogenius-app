import 'package:flutter/material.dart';

import '../models/book_note.dart';
import '../services/translation_service.dart';

/// Displays a single reading note with edit/delete actions.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: note.content,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content
                Text(
                  note.content,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                // Footer: page + date + actions
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
                    const Spacer(),
                    if (onEdit != null)
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: TranslationService.translate(
                                context, 'tooltip_edit_note'),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (onDelete != null)
                      IconButton(
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: TranslationService.translate(
                                context, 'tooltip_delete_note'),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
