import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/book.dart';

import '../models/quote.dart';

class QuoteService {
  static final List<Quote> _fallbackQuotes = [
    Quote(
      text: "A room without books is like a body without a soul.",
      author: "Cicero",
      source: "Philosophy",
    ),
    Quote(
      text: "The person, be it gentleman or lady, who has not pleasure in a good novel, must be intolerably stupid.",
      author: "Jane Austen",
      source: "Northanger Abbey",
    ),
    Quote(
      text: "Good friends, good books, and a sleepy conscience: this is the ideal life.",
      author: "Mark Twain",
      source: "Literature",
    ),
    Quote(
      text: "I have always imagined that Paradise will be a kind of library.",
      author: "Jorge Luis Borges",
      source: "Poem of the Gifts",
    ),
  ];

  /// Fetches a "first sentence" or specific quote for a random book in the user's collection.
  /// If it fails or no suitable book is found, returns a fallback quote.
  Future<Quote> fetchRandomQuote(List<Book> userBooks) async {
    if (userBooks.isEmpty) {
      return _getRandomFallback();
    }

    // Try up to 3 times to get a valid book with a first sentence
    int attempts = 0;
    final random = Random();

    while (attempts < 3) {
      attempts++;
      final book = userBooks[random.nextInt(userBooks.length)];
      
      // If we already have the ISBN, we can try Open Library
      if (book.isbn != null && book.isbn!.isNotEmpty) {
        try {
          final quote = await _fetchOpenLibraryFirstSentence(book);
          if (quote != null) {
            return quote;
          }
        } catch (e) {
          debugPrint('Error fetching quote for ${book.title}: $e');
        }
      }
    }

    return _getRandomFallback();
  }

  Future<Quote?> _fetchOpenLibraryFirstSentence(Book book) async {
    final isbn = book.isbn!.replaceAll('-', '');
    final url = Uri.parse('https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&jscmd=data&format=json');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final key = 'ISBN:$isbn';
        if (data.containsKey(key)) {
          final bookData = data[key];
          
          // Check for first_sentence
          if (bookData is Map && bookData.containsKey('excerpts')) {
             final excerpts = bookData['excerpts'] as List;
             if (excerpts.isNotEmpty) {
               return Quote(
                 text: excerpts.first['text'] ?? '',
                 author: book.author ?? 'Unknown',
                 source: book.title, 
                 coverUrl: book.coverUrl
               );
             }
          }
           // Fallback to first_sentence key if present directly (some OL records structure)
          if (bookData is Map && bookData.containsKey('first_sentence')) {
             final fs = bookData['first_sentence'];
             String text = '';
             if (fs is Map) {
               text = fs['value'];
             } else if (fs is String) {
               text = fs;
             }
             
             if (text.isNotEmpty) {
                return Quote(
                 text: text,
                 author: book.author ?? 'Unknown',
                 source: book.title,
                 coverUrl: book.coverUrl
               );
             }
          }
        }
      }
    } catch (e) {
      debugPrint('OpenLibrary quote fetch failed: $e');
    }
    return null;
  }

  Quote _getRandomFallback() {
    return _fallbackQuotes[Random().nextInt(_fallbackQuotes.length)];
  }
}
