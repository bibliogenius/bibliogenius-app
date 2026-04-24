import '../models/book.dart';

/// Total number of pages across every book the user has marked as finished.
///
/// A book contributes its `pageCount` only when it has both a non-null
/// [Book.finishedReadingAt] and a positive [Book.pageCount]. Books with
/// unknown page count are silently ignored — the alternative (showing `null`
/// as "unknown" or inflating the total with zeros) would be more confusing
/// than the current under-count.
int totalPagesReadFromFinishedBooks(Iterable<Book> books) {
  var sum = 0;
  for (final book in books) {
    if (book.finishedReadingAt == null) continue;
    final pages = book.pageCount;
    if (pages == null || pages <= 0) continue;
    sum += pages;
  }
  return sum;
}
