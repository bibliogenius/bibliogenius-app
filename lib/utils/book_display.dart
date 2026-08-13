import 'package:flutter/widgets.dart';

import '../models/book.dart';
import '../services/translation_service.dart';

/// How a book identifies itself on screen when its own title is missing.
///
/// A manually entered book can carry an empty title: the owner never filled
/// the field, and every transport (hub catalog, LAN sync, relay) forwards it
/// verbatim. Rendering it raw produced blank tiles on the peer screen, with
/// nothing to read, tap or announce to a screen reader.
///
/// The fallback chain is title -> ISBN -> translated placeholder. It is applied
/// at display time, never on the way out: hiding or renaming such books at the
/// push would leave the owner unable to see which of their books needs fixing.
/// Applying it here also repairs the catalogs already cached by peers, which no
/// backend fix can reach.
class BookDisplay {
  const BookDisplay._();

  /// Pure resolution, kept context-free so it can be unit-tested without the
  /// widget tree. [untitledLabel] returns the translated placeholder and is
  /// called only when both title and ISBN are missing: this runs in the build
  /// method of every tile of a library grid, and translating eagerly would pay
  /// a provider lookup per book for a string almost no book needs.
  static String resolveTitle({
    required String title,
    String? isbn,
    required String Function() untitledLabel,
  }) {
    if (title.trim().isNotEmpty) return title;
    if (isbn != null && isbn.trim().isNotEmpty) return isbn;
    return untitledLabel();
  }

  /// Pure screen-reader label for a cover: "title, author" when the author is
  /// known, the title alone otherwise. [title] is expected to come from
  /// [resolveTitle] so a title-less book still announces something (Rule A1).
  static String resolveCoverLabel({required String title, String? author}) {
    if (author != null && author.trim().isNotEmpty) return '$title, $author';
    return title;
  }

  /// Display title for raw catalog fields (hub entries, peer payloads).
  static String titleFor(
    BuildContext context, {
    required String title,
    String? isbn,
  }) => resolveTitle(
    title: title,
    isbn: isbn,
    untitledLabel: () => TranslationService.translate(context, 'book_untitled'),
  );

  /// Display title for a [Book].
  static String titleOf(BuildContext context, Book book) =>
      titleFor(context, title: book.title, isbn: book.isbn);

  /// Cover semantic label for a [Book], built on its display title.
  static String coverLabelOf(BuildContext context, Book book) =>
      resolveCoverLabel(title: titleOf(context, book), author: book.author);
}
