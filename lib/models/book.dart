import '../utils/app_constants.dart';
import '../utils/cover_url_resolver.dart';

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
  final String? language; // ISO language code or full name (e.g., 'fr', 'French')
  final int? availableCopies; // Number of copies with status "available" (from peer)
  final bool private; // When true, hidden from network peers
  final int? pageCount;
  /// When this book was added to its owner's library (maps to the owner's
  /// `books.created_at`). Used by the "new" badge on peer library views:
  /// editorial metadata broadcast by the owner, so every viewer agrees on
  /// which books are recent.
  final DateTime? addedAt;
  /// Timestamp of the last failed hub cover upload for this book. Null when
  /// the most recent attempt succeeded or none ever ran. Present only on the
  /// owner's device (redacted from peer-facing responses): the UI surfaces
  /// a warning badge on the book-details screen while a retry pends.
  final DateTime? hubCoverUploadFailedAt;

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
    this.language,
    this.availableCopies,
    this.private = false,
    this.pageCount,
    this.addedAt,
    this.hubCoverUploadFailedAt,
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
      language: json['language'],
      availableCopies: json['available_copies'],
      private: json['private'] ?? false,
      pageCount: json['page_count'],
      addedAt: json['added_at'] != null
          ? DateTime.tryParse(json['added_at'])
          : null,
      hubCoverUploadFailedAt: json['hub_cover_upload_failed_at'] != null
          ? DateTime.tryParse(json['hub_cover_upload_failed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final now = DateTime.now().toIso8601String();
    return {
      'id': id,
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
      'language': language,
      'available_copies': availableCopies,
      'private': private,
      'page_count': pageCount,
      'added_at': addedAt?.toIso8601String(),
      'hub_cover_upload_failed_at': hubCoverUploadFailedAt?.toIso8601String(),
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Whether this book should display the "new" badge in peer library views.
  /// Single source of truth: the owner's `addedAt` (books.created_at) within
  /// the configured threshold. Books without `addedAt` (not broadcast by the
  /// peer, or own library) are never considered new.
  bool get isNew {
    if (addedAt == null) return false;
    return DateTime.now().difference(addedAt!).inDays <
        AppConstants.newBadgeDays;
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
      price: price,
      digitalFormats: digitalFormats,
      language: language,
      availableCopies: availableCopies,
      private: private,
      pageCount: pageCount,
      addedAt: addedAt,
      hubCoverUploadFailedAt: hubCoverUploadFailedAt,
    );
  }

  /// The persisted cover URL exactly as stored, without any fallback.
  ///
  /// Used by contexts that must NOT fall back to OpenLibrary (peer
  /// views, catalog push). Most screens should prefer [coverUrl] which
  /// goes through `CoverUrlResolver.resolveForLocal`.
  String? get rawCoverUrl => _coverUrl;

  String? get coverUrl =>
      CoverUrlResolver.resolveForLocal(coverUrl: _coverUrl, isbn: isbn);

  String? get largeCoverUrl => CoverUrlResolver.resolveForLocal(
    coverUrl: _coverUrl,
    isbn: isbn,
    large: true,
  );

  /// Whether this book has a cover URL explicitly persisted (not auto-derived from ISBN)
  bool get hasPersistedCover => _coverUrl != null && _coverUrl!.isNotEmpty;

  /// Create a copy with updated cover URL
  Book copyWithCoverUrl(String? newCoverUrl) {
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
      coverUrl: newCoverUrl,
      userRating: userRating,
      owned: owned,
      price: price,
      digitalFormats: digitalFormats,
      language: language,
      availableCopies: availableCopies,
      private: private,
      pageCount: pageCount,
      addedAt: addedAt,
      hubCoverUploadFailedAt: hubCoverUploadFailedAt,
    );
  }

  /// Returns star rating (1-5) from internal 0-10 scale
  double? get starRating => userRating != null ? userRating! / 2.0 : null;
}
