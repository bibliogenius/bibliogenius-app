class Book {
  final int? id;
  final String title;
  final String? isbn;
  final String? summary;
  final String? publisher;
  final int? publicationYear;
  final String? readingStatus;
  final DateTime? finishedReadingAt;
  final DateTime? startedReadingAt;
  final String? author;
  final List<String>? subjects;
  final String? _coverUrl; // Stored cover URL
  final int? userRating; // 0-10 scale
  final bool owned; // Whether I physically own this book (default: true)
  final double? price; // Book price (Bookseller profile)
  final List<String>? digitalFormats; // ["ebook", "audiobook"]

  Book({
    this.id,
    required this.title,
    this.isbn,
    this.summary,
    this.publisher,
    this.publicationYear,
    this.readingStatus,
    this.finishedReadingAt,
    this.startedReadingAt,
    this.author,
    this.subjects,
    String? coverUrl,
    this.userRating,
    this.owned = true,
    this.price, // Optional price
    this.digitalFormats,
  }) : _coverUrl = coverUrl;

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'],
      title: json['title'],
      isbn: json['isbn'],
      summary: json['summary'],
      publisher: json['publisher'],
      publicationYear: json['publication_year'],
      readingStatus: (() {
        final raw = json['reading_status']?.toString();
        var normalized = raw?.toLowerCase().replaceAll(' ', '_');
        // Normalize legacy 'wanted' to 'wanting' for backward compatibility
        if (normalized == 'wanted') normalized = 'wanting';
        return normalized;
      })(),
      finishedReadingAt: json['finished_reading_at'] != null
          ? DateTime.tryParse(json['finished_reading_at'])
          : null,
      startedReadingAt: json['started_reading_at'] != null
          ? DateTime.tryParse(json['started_reading_at'])
          : null,
      author: json['author'],
      coverUrl: (json['cover_url'] as String?)?.trim().isEmpty == true
          ? null
          : json['cover_url'],
      subjects: json['subjects'] != null
          ? List<String>.from(json['subjects'])
          : null,
      userRating: json['user_rating'],
      owned: json['owned'] ?? true,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      digitalFormats: json['digital_formats'] != null
          ? List<String>.from(json['digital_formats'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final now = DateTime.now().toIso8601String();
    return {
      'title': title,
      'isbn': isbn,
      'summary': summary,
      'publisher': publisher,
      'publication_year': publicationYear,
      'reading_status': readingStatus,
      'finished_reading_at': finishedReadingAt?.toIso8601String(),
      'started_reading_at': startedReadingAt?.toIso8601String(),
      'author': author,
      'subjects': subjects,
      'cover_url': _coverUrl,
      'user_rating': userRating,
      'owned': owned,
      'price': price, // Price for Bookseller profile
      'digital_formats': digitalFormats,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Create a copy with updated rating
  Book copyWithRating(int? newRating) {
    return Book(
      id: id,
      title: title,
      isbn: isbn,
      summary: summary,
      publisher: publisher,
      publicationYear: publicationYear,
      readingStatus: readingStatus,
      finishedReadingAt: finishedReadingAt,
      startedReadingAt: startedReadingAt,
      author: author,
      subjects: subjects,
      coverUrl: _coverUrl,
      userRating: newRating,
      owned: owned,
      price: price, // Preserve price
      digitalFormats: digitalFormats, // Preserve formats
    );
  }

  String? get coverUrl {
    if (_coverUrl != null && _coverUrl.isNotEmpty) return _coverUrl;
    if (isbn != null && isbn!.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
    }
    return null;
  }

  String? get largeCoverUrl {
    if (_coverUrl != null && _coverUrl.isNotEmpty)
      return _coverUrl; // Or try to get large version if possible
    if (isbn != null && isbn!.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg?default=false';
    }
    return null;
  }

  /// Whether this book has a cover URL explicitly persisted (not auto-derived from ISBN)
  bool get hasPersistedCover => _coverUrl != null && _coverUrl!.isNotEmpty;

  /// Returns star rating (1-5) from internal 0-10 scale
  double? get starRating => userRating != null ? userRating! / 2.0 : null;
}
