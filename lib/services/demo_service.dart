import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_service.dart';
import '../models/book.dart';

class DemoService {
  static Future<void> importDemoBooks(BuildContext context) async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    final demoBooks = [
      {
        'title': 'The Great Gatsby',
        'author': 'F. Scott Fitzgerald',
        'isbn': '9780743273565',
        'publisher': 'Scribner',
        'publication_year': 1925,
        'description':
            'The story of the fabulously wealthy Jay Gatsby and his love for the beautiful Daisy Buchanan.',
        'cover_url':
            'https://covers.openlibrary.org/b/isbn/9780743273565-L.jpg',
      },
      {
        'title': '1984',
        'author': 'George Orwell',
        'isbn': '9780451524935',
        'publisher': 'Signet Classic',
        'publication_year': 1949,
        'description':
            'A dystopian social science fiction novel and cautionary tale about the future.',
        'cover_url':
            'https://covers.openlibrary.org/b/isbn/9780451524935-L.jpg',
      },
      {
        'title': 'Le Petit Prince',
        'author': 'Antoine de Saint-Exupéry',
        'isbn': '9782070408504',
        'publisher': 'Gallimard',
        'publication_year': 1943,
        'description':
            "Le Petit Prince est une oeuvre de langue francaise, la plus connue d'Antoine de Saint-Exupery.",
        'cover_url':
            'https://covers.openlibrary.org/b/isbn/9782070408504-L.jpg',
      },
      {
        'title': 'Dune',
        'author': 'Frank Herbert',
        'isbn': '9780441013593',
        'publisher': 'Ace',
        'publication_year': 1965,
        'description':
            'Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides.',
        'cover_url':
            'https://covers.openlibrary.org/b/isbn/9780441013593-L.jpg',
      },
    ];

    for (final bookData in demoBooks) {
      try {
        // Create the book
        final response = await apiService.createBook(bookData);

        // Extract book ID from response and create a copy
        if (response.data != null) {
          String? bookId;
          if (response.data is Map) {
            bookId = response.data['id'] as String?;
          } else if (response.data is Book) {
            bookId = (response.data as Book).id;
          }

          if (bookId != null) {
            // Create a default copy for this book
            await apiService.createCopy({
              'book_id': bookId,
              'status': 'available',
              'condition': 'good',
              'notes': 'Demo copy',
            });
            debugPrint('Created copy for book ID: $bookId');
          }
        }
      } catch (e) {
        // Ignore errors for individual books (e.g. duplicates)
        debugPrint('Error importing demo book: $e');
      }
    }
  }
}
