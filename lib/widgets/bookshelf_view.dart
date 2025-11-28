import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_spine.dart';

class BookshelfView extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;

  const BookshelfView({
    super.key,
    required this.books,
    required this.onBookTap,
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
                child: BookSpine(
                  book: book,
                  height:
                      140 + ((book.id ?? 0) % 4) * 10.0, // Vary height slightly
                  width: 35 + ((book.id ?? 0) % 3) * 5.0, // Vary width slightly
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
