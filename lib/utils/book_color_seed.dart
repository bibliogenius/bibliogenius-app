import '../models/book.dart';

/// Stable, non-zero seed for deriving placeholder colors and sizes of a book.
///
/// Falls back in order: local DB id -> ISBN hash -> (title + author) hash.
/// This matters for peer libraries and hub catalogs where `book.id` is
/// commonly null -- without the fallback, every book would collapse to seed
/// 0 and render with the same hue and dimensions.
int bookColorSeed(Book book) {
  if (book.id != null && book.id != 0) return book.id!;
  final isbn = book.isbn;
  if (isbn != null && isbn.isNotEmpty) return isbn.hashCode;
  final author = book.author ?? '';
  final composite = '${book.title}|$author';
  final hash = composite.hashCode;
  return hash == 0 ? 1 : hash;
}
