import '../models/book.dart';

/// Which field drives the primary ordering of the library list.
///
/// [shelf] is the order a reader gave a shelf by dragging its books (the
/// `shelf_position` column). It only means something while a shelf is open:
/// everywhere else the list falls back to author A-Z (see
/// `book_list_screen.dart`).
enum SortBy { author, title, shelf }

/// Direction of the primary ordering. Secondary keys are always ascending.
enum SortDir { asc, desc }

bool _isAuthorEmpty(String? author) => author == null || author.trim().isEmpty;

String _surname(String author) {
  final parts = author.trim().split(RegExp(r'\s+'));
  return parts.last.toLowerCase();
}

int _compareByAuthor(Book a, Book b) {
  final aEmpty = _isAuthorEmpty(a.author);
  final bEmpty = _isAuthorEmpty(b.author);
  if (aEmpty && bEmpty) return 0;
  if (aEmpty) return 1;
  if (bEmpty) return -1;

  final cmpSurname = _surname(a.author!).compareTo(_surname(b.author!));
  if (cmpSurname != 0) return cmpSurname;
  return a.author!.toLowerCase().compareTo(b.author!.toLowerCase());
}

int _compareByTitle(Book a, Book b) {
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// A book never placed by hand has no position and comes after every placed
/// one. SQLite would put these NULLs first: the order is decided here, not
/// by the query.
int _compareByShelfPosition(Book a, Book b) {
  final ap = a.shelfPosition;
  final bp = b.shelfPosition;
  if (ap == null && bp == null) return 0;
  if (ap == null) return 1;
  if (bp == null) return -1;
  return ap.compareTo(bp);
}

/// Orders two books for the library list view.
///
/// Rules:
/// - Primary key follows [sortBy] and [dir].
/// - Secondary key is always ascending (within a shared primary value, title
///   stays A-Z even when sorting authors Z-A, and vice versa).
/// - When sorting by author, books with a missing or whitespace-only author
///   are always placed at the bottom, regardless of [dir]. Two empty-author
///   books fall through to the title secondary.
/// - The shelf order has no reverse: [dir] is ignored, and ties as well as
///   the unplaced tail read as the library does by default, author A-Z.
int compareBooks(Book a, Book b, SortBy sortBy, SortDir dir) {
  if (sortBy == SortBy.shelf) {
    final byPosition = _compareByShelfPosition(a, b);
    if (byPosition != 0) return byPosition;
    return compareBooks(a, b, SortBy.author, SortDir.asc);
  }

  if (sortBy == SortBy.author) {
    final aEmpty = _isAuthorEmpty(a.author);
    final bEmpty = _isAuthorEmpty(b.author);
    if (aEmpty && !bEmpty) return 1;
    if (!aEmpty && bEmpty) return -1;
  }

  final byTitle = sortBy == SortBy.title;
  var primary = byTitle ? _compareByTitle(a, b) : _compareByAuthor(a, b);
  if (dir == SortDir.desc) primary = -primary;
  if (primary != 0) return primary;

  return byTitle ? _compareByAuthor(a, b) : _compareByTitle(a, b);
}

extension BookSortList on List<Book> {
  void sortWith(SortBy sortBy, SortDir dir) {
    sort((a, b) => compareBooks(a, b, sortBy, dir));
  }
}
