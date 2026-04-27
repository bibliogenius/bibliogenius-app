import 'package:flutter/material.dart';
import '../models/book.dart';
import '../utils/book_color_seed.dart';
import 'book_spine.dart';

class BookshelfView extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;

  /// Optional widget shown below the book grid (e.g. loading indicator).
  final Widget? footer;

  const BookshelfView({
    super.key,
    required this.books,
    required this.onBookTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Wrap(
                spacing: 0, // No spacing between books on the same shelf
                runSpacing: 20, // Spacing between shelves
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: books.map((book) {
                  final seed = bookColorSeed(book);
                  return GestureDetector(
                    onTap: () => onBookTap(book),
                    child: BookSpine.fromBook(
                      book: book,
                      height: 220 + (seed.abs() % 4) * 12.0,
                      width: 60 + (seed.abs() % 3) * 6.0,
                      showNewBand: book.isNew,
                    ),
                  );
                }).toList(),
              ),
              if (footer != null) footer!,
            ],
          ),
        );
      },
    );
  }
}
