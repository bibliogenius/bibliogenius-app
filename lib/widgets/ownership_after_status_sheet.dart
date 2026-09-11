import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/translation_service.dart';

/// What the reader answered to [showOwnershipAfterStatusSheet].
enum OwnershipAnswer {
  /// "I own this book": claim it, it joins the default view.
  own,

  /// "I do not own this book": leave it, it stays under its status filter.
  notOwned,

  /// "Show everything in my library": widen the default view for good, so no
  /// book can disappear again and the question never comes back.
  showAll,
}

/// "Is this book on your shelves?", asked when a book the reader does not have
/// receives a reading status that is not a wish.
///
/// A reading status never touches `owned`, and the default library view shows
/// possession only (ADR-063). Marking a wish "read" therefore made the book
/// leave "All my books" while staying under "Read", and readers reported it as
/// lost. The acquisition side already asks the mirror question; this closes
/// the loop from the status side.
///
/// [offerShowAll] adds a third row, set apart, that widens the default view
/// instead of answering about this one book. It is not offered the first
/// time: one book read without owning it is an anecdote, the second is a
/// habit, and the row would otherwise read as "make the question stop".
///
/// A dismissed sheet returns null; callers treat it like [OwnershipAnswer.notOwned]
/// minus the mark: the reader asked for a status change and gets it either
/// way, the question is only about where the book shows up afterwards.
Future<OwnershipAnswer?> showOwnershipAfterStatusSheet(
  BuildContext context, {
  required Book book,
  bool offerShowAll = false,
}) {
  return showModalBottomSheet<OwnershipAnswer>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final small = theme.textTheme.bodySmall;
      String t(String key) => TranslationService.translate(ctx, key);

      // Scrolls rather than overflows: three rows with subtitles do not fit
      // the default sheet height on a short phone or at a large text scale.
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Semantics(
                  header: true,
                  child: Text(
                    t('status_change_ownership_title'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                key: const Key('ownershipAfterStatusYes'),
                leading: Icon(
                  Icons.library_books_rounded,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(t('own_this_book')),
                subtitle: Text(
                  t('status_change_ownership_yes_desc'),
                  style: small,
                ),
                onTap: () => Navigator.pop(ctx, OwnershipAnswer.own),
              ),
              ListTile(
                key: const Key('ownershipAfterStatusNo'),
                leading: Icon(
                  Icons.bookmark_add_outlined,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(t('book_ownership_not_owned')),
                subtitle: Text(
                  t('status_change_ownership_no_desc'),
                  style: small,
                ),
                onTap: () => Navigator.pop(ctx, OwnershipAnswer.notOwned),
              ),
              if (offerShowAll) ...[
                const Divider(height: 1),
                ListTile(
                  key: const Key('ownershipAfterStatusShowAll'),
                  leading: Icon(Icons.visibility_outlined, color: cs.primary),
                  title: Text(t('status_change_ownership_show_all')),
                  subtitle: Text(
                    t('status_change_ownership_show_all_desc'),
                    style: small,
                  ),
                  onTap: () => Navigator.pop(ctx, OwnershipAnswer.showAll),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}
