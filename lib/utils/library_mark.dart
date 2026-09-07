/// What the reader's OWN library has to say about a book sitting on someone
/// else's shelf.
///
/// The point of the mark is a decision the reader is about to make: asking to
/// borrow, or buying, a book they already have. Possession therefore outranks
/// everything else, having read it comes next, and a wish last.
enum LibraryMark {
  /// The reader owns it and has read it.
  ownedAndRead,

  /// The reader owns it.
  owned,

  /// The reader has read it without owning it.
  read,

  /// The reader wants it.
  wanted,
}

/// The mark to show, or null when the reader's library has nothing to say.
///
/// Single source of truth for the rule, so the peer catalogue and any later
/// surface (a search result, a directory catalogue) cannot drift apart. Do not
/// re-derive it inline in a screen.
///
/// [owned] is null when the library does not hold the book at all, which is a
/// different statement from holding it unowned: an unowned row is a wish, a
/// borrowed copy, or a book read elsewhere.
LibraryMark? libraryMarkFor({
  required bool? owned,
  required String? readingStatus,
  bool recordedReadHere = false,
}) {
  final read = recordedReadHere || readingStatus == 'read';

  if (owned == true) {
    return read ? LibraryMark.ownedAndRead : LibraryMark.owned;
  }
  if (read) return LibraryMark.read;
  if (readingStatus == 'wanting') return LibraryMark.wanted;
  return null;
}
