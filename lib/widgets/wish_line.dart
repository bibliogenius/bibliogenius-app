import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/translation_service.dart';

/// The shared wish on a book, as a line under the status pill.
///
/// Rendered only when the wish has something to add to the pill: the names
/// of the readers who made it, or the wish itself when the pill shows the
/// current reader's own status instead. In that second case the line also
/// carries the one gesture the status picker cannot offer that reader:
/// taking the book off the wishlist without touching anyone's reading.
class WishLine extends StatelessWidget {
  final Book book;
  final VoidCallback? onRemove;

  const WishLine({super.key, required this.book, this.onRemove});

  /// Whether the line has anything to say for [book].
  static bool shows(Book book) =>
      book.isWished &&
      (book.readingStatus != 'wanting' || (book.wishedBy?.isNotEmpty ?? false));

  @override
  Widget build(BuildContext context) {
    if (!shows(book)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final names = book.wishedBy;
    final label = names != null && names.isNotEmpty
        ? TranslationService.translate(
            context,
            'wishlist_wished_by',
            params: {'names': names.join(', ')},
          )
        : TranslationService.translate(context, 'reading_status_wanting');
    final removable = onRemove != null && book.readingStatus != 'wanting';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (removable)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: TranslationService.translate(
                context,
                'wishlist_remove_action',
              ),
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
