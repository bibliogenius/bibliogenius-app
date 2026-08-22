/// Pure selectors behind the statistics screens (ADR-063).
///
/// The summary statistics describe the user's physical library: the same
/// scope as the default library view (owned, or present through an on-loan
/// copy). Counting raw book rows would let wishlist entries and
/// read-but-not-owned books inflate the totals and the completion rate, and
/// `!owned` is not a borrow marker: it also matches those same books.
///
/// Extracted from `StatisticsScreen` so these rules can be tested directly.
library;

import '../models/book.dart';
import 'book_filters.dart';

/// The books the summary totals describe: the physical library.
///
/// The "hide borrowed books" display preference does not apply to statistics;
/// a lent or borrowed copy is physically part of the library it measures.
List<Book> physicalLibrary(List<Book> books) =>
    books.where((b) => matchesDefaultView(b, showBorrowed: true)).toList();

/// The books currently borrowed from someone else, read from the copy-backed
/// possession flag. `!owned` is not a borrow marker: it also matches wishlist
/// entries and books read without ever being owned.
List<Book> borrowedBooks(List<Book> books) =>
    books.where((b) => b.isBorrowed ?? false).toList();
