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
  final String? _coverUrl; // Stored cover URL

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
    String? coverUrl,
  }) : _coverUrl = coverUrl;

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'],
      title: json['title'],
      isbn: json['isbn'],
      summary: json['summary'],
      publisher: json['publisher'],
      publicationYear: json['publication_year'],
      readingStatus: json['reading_status'],
      finishedReadingAt: json['finished_reading_at'] != null 
          ? DateTime.tryParse(json['finished_reading_at']) 
          : null,
      startedReadingAt: json['started_reading_at'] != null 
          ? DateTime.tryParse(json['started_reading_at']) 
          : null,
      author: json['author'],
      coverUrl: json['cover_url'],
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
      'cover_url': _coverUrl,
      'created_at': now,
      'updated_at': now,
    };
  }


  String? get coverUrl {
    if (_coverUrl != null && _coverUrl!.isNotEmpty) return _coverUrl;
    if (isbn != null && isbn!.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg';
    }
    return null;
  }

  String? get largeCoverUrl {
    if (_coverUrl != null && _coverUrl!.isNotEmpty) return _coverUrl; // Or try to get large version if possible
    if (isbn != null && isbn!.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg';
    }
    return null;
  }
}
