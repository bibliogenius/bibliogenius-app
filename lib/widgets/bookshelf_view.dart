import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_spine.dart';

class BookshelfView extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;
  /// Set of book IDs that should display a "new" band on their spine.
  final Set<int> newBookIds;

  const BookshelfView({
    super.key,
    required this.books,
    required this.onBookTap,
    this.newBookIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            spacing: 0, // No spacing between books on the same shelf
            runSpacing: 20, // Spacing between shelves
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: books.map((book) {
              return GestureDetector(
                onTap: () => onBookTap(book),
                child: BookSpine.fromBook(
                  book: book,
                  height:
                      220 + ((book.id ?? 0) % 4) * 12.0, // Vary height slightly
                  width: 60 + ((book.id ?? 0) % 3) * 6.0, // Vary width slightly
                  showNewBand: newBookIds.contains(book.id),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
