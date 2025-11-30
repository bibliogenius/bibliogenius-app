import 'package:dio/dio.dart';

class OpenLibraryBook {
  final String title;
  final String author;
  final String? isbn;
  final String? publisher;
  final int? year;
  final String? coverUrl;
  final String? key;

  OpenLibraryBook({
    required this.title,
    required this.author,
    this.isbn,
    this.publisher,
    this.year,
    this.coverUrl,
    this.key,
  });

  factory OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    // Extract author
    String author = 'Unknown Author';
    if (json['author_name'] != null && (json['author_name'] as List).isNotEmpty) {
      author = json['author_name'][0];
    }

    // Extract ISBN (prefer 13, then 10)
    String? isbn;
    if (json['isbn'] != null && (json['isbn'] as List).isNotEmpty) {
      isbn = json['isbn'][0];
    }

    // Extract Publisher
    String? publisher;
    if (json['publisher'] != null && (json['publisher'] as List).isNotEmpty) {
      publisher = json['publisher'][0];
    }

    // Extract Year
    int? year;
    if (json['first_publish_year'] != null) {
      year = json['first_publish_year'];
    }

    // Extract Cover
    String? coverUrl;
    if (json['cover_i'] != null) {
      coverUrl = 'https://covers.openlibrary.org/b/id/${json['cover_i']}-L.jpg';
    }

    return OpenLibraryBook(
      title: json['title'] ?? 'Unknown Title',
      author: author,
      isbn: isbn,
      publisher: publisher,
      year: year,
      coverUrl: coverUrl,
      key: json['key'],
    );
  }
}

class OpenLibraryService {
  final Dio _dio = Dio();
  final String _baseUrl = 'https://openlibrary.org';

  Future<List<OpenLibraryBook>> searchBooks(String query) async {
    if (query.length < 3) return [];

    try {
      final response = await _dio.get(
        '$_baseUrl/search.json',
        queryParameters: {
          'q': query,
          'limit': 10,
          'fields': 'title,author_name,isbn,publisher,first_publish_year,cover_i,key',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['docs'] != null) {
          return (data['docs'] as List)
              .map((doc) => OpenLibraryBook.fromJson(doc))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error searching Open Library: $e');
      return [];
    }
  }
}
