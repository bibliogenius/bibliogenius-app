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

/// Minimum number of books carrying a finish date before the dashboard
/// surfaces the "recently finished" strip.
///
/// Below this the strip would show one or two covers and mostly repeat the
/// recent-additions block sitting right under it, so it stays hidden until
/// the reading history is worth its own row.
const int kMinRecentlyFinishedBooks = 3;

/// The dashboard's "recently finished" selection: books the user finished,
/// most recent first, capped at [limit].
///
/// Only books with a [Book.finishedReadingAt] date take part. The strip is
/// ordered by that date, and a book marked read without one (the "No Date"
/// option in the status quick-action) has no place in that ordering, unlike
/// [totalPagesReadFromFinishedBooks], which counts it.
///
/// Returns an empty list when fewer than [kMinRecentlyFinishedBooks] books
/// carry a date, so the caller can render on a non-empty check alone. The
/// threshold is measured on the whole library, before the [limit] cap.
List<Book> recentlyFinishedBooks(Iterable<Book> books, {int limit = 10}) {
  final finished = books.where((b) => b.finishedReadingAt != null).toList();
  if (finished.length < kMinRecentlyFinishedBooks) return const [];
  finished.sort((a, b) => b.finishedReadingAt!.compareTo(a.finishedReadingAt!));
  return finished.take(limit).toList();
}
