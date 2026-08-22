import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_cover_card.dart';

/// Whether the "new" band differentiates anything: when every book is new
/// (fresh import, brand new library), tagging them all is pure noise.
///
/// Evaluate it on the FULL library, never on a filtered or searched subset:
/// a search that isolates one fresh book is an all-new list, and the band
/// must survive there.
bool newBadgeIsInformative(List<Book> books) => books.any((b) => !b.isNew);

class BookCoverGrid extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;
  final void Function(Book book, String newStatus)? onStatusChanged;

  /// Already-translated wishlist availability labels, keyed by ISBN.
  /// Only the wishlist filter passes this; books without an entry render
  /// no badge.
  final Map<String, String>? availabilityLabels;

  /// Whether new books wear the band. Callers that display a FILTERED subset
  /// must pass [newBadgeIsInformative] of the full library; when null, the
  /// grid falls back to evaluating its own (assumed complete) list.
  final bool? showNewBadge;

  const BookCoverGrid({
    super.key,
    required this.books,
    required this.onBookTap,
    this.onStatusChanged,
    this.availabilityLabels,
    this.showNewBadge,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_books, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No books found',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150, // Controls the width of items
        childAspectRatio: 0.65, // Standard book ratio (width / height)
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return BookCoverCard(
          book: book,
          onTap: () => onBookTap(book),
          onStatusChanged: onStatusChanged != null
              ? (status) => onStatusChanged!(book, status)
              : null,
          // Map lookup with a null ISBN just returns null (no badge).
          availabilityLabel: availabilityLabels?[book.isbn],
          showNewBadge: showNewBadge ?? newBadgeIsInformative(books),
        );
      },
    );
  }
}
