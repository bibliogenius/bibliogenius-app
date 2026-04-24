import '../models/book.dart';

/// Total number of pages across every book the user considers read.
///
/// A book counts as read when [Book.readingStatus] is `'read'` OR
/// [Book.finishedReadingAt] is set — users can mark a book as read without
/// picking a date (see the "No Date" option in the status quick-action), so
/// requiring the date here would silently exclude those books.
///
/// Books with unknown or non-positive [Book.pageCount] are skipped: the
/// alternative (counting them as zero) would understate the real total only
/// slightly but mislead the user into thinking their read pile is smaller
/// than it is.
int totalPagesReadFromFinishedBooks(Iterable<Book> books) {
  var sum = 0;
  for (final book in books) {
    final isRead =
        book.readingStatus == 'read' || book.finishedReadingAt != null;
    if (!isRead) continue;
    final pages = book.pageCount;
    if (pages == null || pages <= 0) continue;
    sum += pages;
  }
  return sum;
}
