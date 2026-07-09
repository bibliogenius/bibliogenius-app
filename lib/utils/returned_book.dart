/// Rules for what to offer after a borrowed book has been returned.
///
/// The app never deletes a book on its own: returning a copy removes the copy and
/// leaves the book, because it may carry reading dates, a rating and notes the
/// reader entered. Removing it from the library stays an explicit user action, and
/// these helpers decide only whether, and how loudly, to offer it.
library;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/copy.dart';
import '../services/translation_service.dart';

/// Whether the returned book is a candidate for removal at all.
///
/// Only a book the user does not own, and holds no other copy of, is worth
/// offering to remove. [copiesBeforeReturn] is the local view taken before the
/// backend deleted the borrowed copy, so a single copy means none is left.
bool canOfferToRemove(Book book, List<Copy> copiesBeforeReturn) {
  if (book.owned) return false;
  return copiesBeforeReturn.length <= 1;
}

/// Whether the book received nothing from the user, in which case removing it
/// loses nothing and the offer can be the emphasised action.
///
/// A book left at its default reading status, unrated and unread, is one the app
/// created for the loan rather than one the reader made their own.
bool returnedBookLooksUntouched(Book book) {
  if (book.userRating != null) return false;
  if (book.startedReadingAt != null || book.finishedReadingAt != null) {
    return false;
  }
  final status = book.readingStatus;
  return status == null || status.isEmpty || status == 'to_read';
}

/// Offer to remove a book that has just been given back.
///
/// Returns false unless the user explicitly picks removal, so dismissing the
/// dialog keeps the book. Removal is emphasised only when the book carries
/// nothing the reader entered, and it is never the default action.
Future<bool> askToRemoveReturnedBook(BuildContext context, Book book) async {
  final untouched = returnedBookLooksUntouched(book);

  final removed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final keep = TranslationService.translate(ctx, 'return_keep_action');
      final remove = TranslationService.translate(ctx, 'return_remove_action');
      final keepAction = TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(keep),
      );
      final removeAction = TextButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(remove),
      );

      return AlertDialog(
        title: Text(TranslationService.translate(ctx, 'return_kept_title')),
        content: Text(TranslationService.translate(ctx, 'return_kept_body')),
        actions: untouched
            ? [
                keepAction,
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(remove),
                ),
              ]
            : [
                removeAction,
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(keep),
                ),
              ],
      );
    },
  );
  return removed ?? false;
}
