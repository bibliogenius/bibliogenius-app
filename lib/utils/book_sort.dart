import '../models/book.dart';

/// Which field drives the primary ordering of the library list.
enum SortBy { author, title }

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

/// Orders two books for the library list view.
///
/// Rules:
/// - Primary key follows [sortBy] and [dir].
/// - Secondary key is always ascending (within a shared primary value, title
///   stays A-Z even when sorting authors Z-A, and vice versa).
/// - When sorting by author, books with a missing or whitespace-only author
///   are always placed at the bottom, regardless of [dir]. Two empty-author
///   books fall through to the title secondary.
int compareBooks(Book a, Book b, SortBy sortBy, SortDir dir) {
  if (sortBy == SortBy.author) {
    final aEmpty = _isAuthorEmpty(a.author);
    final bEmpty = _isAuthorEmpty(b.author);
    if (aEmpty && !bEmpty) return 1;
    if (!aEmpty && bEmpty) return -1;
  }

  int primary;
  switch (sortBy) {
    case SortBy.author:
      primary = _compareByAuthor(a, b);
      break;
    case SortBy.title:
      primary = _compareByTitle(a, b);
      break;
  }
  if (dir == SortDir.desc) primary = -primary;
  if (primary != 0) return primary;

  switch (sortBy) {
    case SortBy.author:
      return _compareByTitle(a, b);
    case SortBy.title:
      return _compareByAuthor(a, b);
  }
}

extension BookSortList on List<Book> {
  void sortWith(SortBy sortBy, SortDir dir) {
    sort((a, b) => compareBooks(a, b, sortBy, dir));
  }
}
