import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_cover_card.dart';

class BookCoverGrid extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;

  const BookCoverGrid({
    super.key,
    required this.books,
    required this.onBookTap,
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey,
                  ),
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
        );
      },
    );
  }
}
