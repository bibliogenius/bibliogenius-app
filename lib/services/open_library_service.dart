import 'package:dio/dio.dart';

class OpenLibraryBook {
  final String title;
  final String author;
  final String? isbn;
  final String? publisher;
  final int? year;
  final String? coverUrl;
  final String? key;
  final String? summary;

  OpenLibraryBook({
    required this.title,
    required this.author,
    this.isbn,
    this.publisher,
    this.year,
    this.coverUrl,
    this.key,
    this.summary,
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

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'author': author,
      'isbn': isbn,
      'publisher': publisher,
      'publication_year': year?.toString(),
      'cover_url': coverUrl,
      'key': key,
    };
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

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    try {
      // Use the precise /isbn/ endpoint for exact ISBN matching
      final response = await _dio.get('$_baseUrl/isbn/$isbn.json');

      if (response.statusCode == 200) {
        final data = response.data;
        
        // Extract basic info
        String title = data['title'] ?? 'Unknown Title';
        String? publisher;
        int? year;
        String? coverUrl;
        
        // Extract publishers
        if (data['publishers'] != null && (data['publishers'] as List).isNotEmpty) {
          publisher = data['publishers'][0];
        }
        
        // Extract publish date and parse year
        if (data['publish_date'] != null) {
          final publishDate = data['publish_date'] as String;
          // Try to extract year from various formats like "1995", "January 1995", "Jan 01, 1995"
          final yearMatch = RegExp(r'\d{4}').firstMatch(publishDate);
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(0)!);
          }
        }
        
        // Get cover from cover IDs
        if (data['covers'] != null && (data['covers'] as List).isNotEmpty) {
          final coverId = data['covers'][0];
          coverUrl = 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
        }
        
        // Extract author - this is the tricky part
        String author = 'Unknown Author';
        
        // Try to get author from the edition data
        if (data['authors'] != null && (data['authors'] as List).isNotEmpty) {
          // Authors in /isbn/ endpoint are usually just references like {"key": "/authors/OL1234A"}
          // We need to fetch the actual author name
          try {
            final authorRef = data['authors'][0];
            if (authorRef is Map && authorRef['key'] != null) {
              final authorKey = authorRef['key'] as String;
              final authorResponse = await _dio.get('$_baseUrl$authorKey.json',
                options: Options(
                  validateStatus: (status) => status! < 500, // Accept 4xx errors gracefully
                  receiveTimeout: const Duration(seconds: 3), // Don't hang on slow requests
                ),
              );
              
              if (authorResponse.statusCode == 200 && authorResponse.data['name'] != null) {
                author = authorResponse.data['name'];
              }
            }
          } catch (e) {
            print('Failed to fetch author details: $e');
            // Keep 'Unknown Author' as fallback
          }
        }
        
        // Try to get author from 'by_statement' field as last resort
        if (author == 'Unknown Author' && data['by_statement'] != null) {
          author = data['by_statement'] as String;
        }
        
        return OpenLibraryBook(
          title: title,
          author: author,
          isbn: isbn,
          publisher: publisher,
          year: year,
          coverUrl: coverUrl,
          key: data['key'],
        );
      }
      return null;
    } catch (e) {
      print('Error looking up ISBN in OpenLibrary: $e');
      return null;
    }
  }
}
