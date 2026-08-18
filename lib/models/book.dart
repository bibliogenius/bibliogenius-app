import '../utils/app_constants.dart';
import '../utils/cover_url_resolver.dart';
import '../utils/local_cover_resolver.dart';

class Book {
  /// Cross-device stable identity (the book's uuid). Backend-owned; null for
  /// peer/transient books or rows not yet persisted. This is what addresses a
  /// book over FFI, in routes, for sub-resources (copies, notes, loan
  /// duration), and for covers on disk (`<uuid>.jpg`).
  final String? id;

  /// Backwards-compatible alias: the uuid is now the primary [id].
  String? get uuid => id;

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
  final String?
  language; // ISO language code or full name (e.g., 'fr', 'French')
  final int?
  availableCopies; // Number of copies with status "available" (from peer)
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

  /// Whether at least one copy of this book is currently borrowed, from a peer
  /// or from a contact. Possession, not reading: a borrowed book carries its own
  /// [readingStatus] like any other.
  ///
  /// Independent of [isLent]: our copy can be at a friend's while another copy
  /// sits borrowed on our shelf, so both can be true. Null means UNKNOWN, never
  /// false: only the owner's library listing computes it. Use [isBorrowed] over
  /// `readingStatus == 'borrowed'`, which the backend no longer emits.
  final bool? isBorrowed;

  /// Whether at least one copy the user owns is currently lent out.
  /// See [isBorrowed] for the axis and the null semantics.
  final bool? isLent;

  /// Peer catalog only: true when the OWNING PEER wants this book (their
  /// wishlist, broadcast as an additive wire flag). Null means "not
  /// stated" (older peer build, or simply not wanted) and must never be
  /// inferred from [owned] being false, which also covers books the peer
  /// merely borrowed. Round-trips through toJson so the peer-cache upload
  /// (cachePeerBooks) preserves it.
  final bool? wanted;

  /// Whether the book sits on either side of a loan.
  ///
  /// An unknown flag reads as "no", not as "yes": a book whose possession was
  /// never computed must not claim to be on loan. This is the one place that
  /// rule lives, so filters and badges cannot drift apart.
  bool get isOnLoan => (isBorrowed ?? false) || (isLent ?? false);

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
    this.isBorrowed,
    this.isLent,
    this.wanted,
  }) : _coverUrl = coverUrl;

  /// Coerce a JSON value into a nullable int, tolerating numeric strings.
  ///
  /// Peer catalogues can arrive from heterogeneous sources (different app
  /// versions, import pipelines) where a numeric field such as
  /// `publication_year` is serialized as a string ("2014"). A plain
  /// `json['x'] as int?` throws "type 'String' is not a subtype of type
  /// 'int?'" and aborts the whole sync, so we parse defensively here.
  static int? _asIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Coerce a JSON value into a nullable bool. Absent stays absent: null means
  /// "the sender did not compute this", which is not the same as false.
  static bool? _asBoolOrNull(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return null;
  }

  /// The raw `reading_status`, lowercased, with legacy spellings folded in.
  static String? _rawReadingStatus(Map<String, dynamic> json) {
    final raw = json['reading_status']?.toString();
    var normalized = raw?.toLowerCase().replaceAll(' ', '_');
    // Normalize legacy 'wanted' to 'wanting' for backward compatibility
    if (normalized == 'wanted') normalized = 'wanting';
    return normalized;
  }

  /// The reading status, stripped of the possession values an older backend
  /// used to write over it. "borrowed" and "lent" were never reading statuses
  /// and are absent from the picker: surfacing them paints the badge a default
  /// blue and opens the picker on a value it does not offer.
  static String? _readingStatusOf(String? rawStatus) {
    if (rawStatus == 'borrowed' || rawStatus == 'lent') return null;
    return rawStatus;
  }

  /// Reads a legacy possession value out of `reading_status`. Returns null when
  /// the field says nothing about [state], so a caller's `??` keeps looking.
  static bool? _legacyLoanState(String? rawStatus, String state) {
    return rawStatus == state ? true : null;
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    // Normalized once: three readers below share it, and this runs per book on
    // every catalogue decode.
    final rawStatus = _rawReadingStatus(json);
    return Book(
      // Identity is the uuid, carried under `uuid` or (post-flip) `id`.
      id: (json['uuid'] ?? json['id'])?.toString(),
      title: json['title'],
      isbn: json['isbn'],
      summary: json['summary'],
      publisher: json['publisher'],
      publicationYear: _asIntOrNull(json['publication_year']),
      readingStatus: _readingStatusOf(rawStatus),
      // A payload written before the possession flags existed smuggled the loan
      // state through `reading_status`. Recover it rather than lose it, and let
      // an explicit flag win when both are present.
      isBorrowed:
          _asBoolOrNull(json['is_borrowed']) ??
          _legacyLoanState(rawStatus, 'borrowed'),
      isLent:
          _asBoolOrNull(json['is_lent']) ?? _legacyLoanState(rawStatus, 'lent'),
      // Absent stays absent: no fallback on owned == false (see field doc).
      wanted: _asBoolOrNull(json['wanted']),
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
      userRating: _asIntOrNull(json['user_rating']),
      owned: json['owned'] ?? true,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      digitalFormats: json['digital_formats'] != null
          ? List<String>.from(json['digital_formats'])
          : null,
      language: json['language'],
      availableCopies: _asIntOrNull(json['available_copies']),
      private: json['private'] ?? false,
      pageCount: _asIntOrNull(json['page_count']),
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
      // The uuid is the identity. `Book.fromJson` reads `uuid ?? id`, so this
      // single `id` key round-trips (e.g. route extra). Backend ignores it on write.
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
      if (wanted != null) 'wanted': wanted,
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
      isBorrowed: isBorrowed,
      isLent: isLent,
      wanted: wanted,
    );
  }

  /// The persisted cover URL exactly as stored, without any fallback.
  ///
  /// Used by contexts that must NOT fall back to OpenLibrary (peer
  /// views, catalog push). Most screens should prefer [coverUrl] which
  /// goes through `CoverUrlResolver.resolveForLocal`.
  String? get rawCoverUrl => _coverUrl;

  String? get coverUrl => _rebaseLocal(
    CoverUrlResolver.resolveForLocal(coverUrl: _coverUrl, isbn: isbn),
  );

  String? get largeCoverUrl => _rebaseLocal(
    CoverUrlResolver.resolveForLocal(
      coverUrl: _coverUrl,
      isbn: isbn,
      large: true,
    ),
  );

  /// Re-bases a resolved local cover path onto the current covers directory
  /// (iOS data-container UUID drift). No-op for http/api/null values and when
  /// the uuid is unknown. Covers on disk are named `<uuid>.jpg`, so the uuid
  /// [id] drives the re-base. See [LocalCoverResolver].
  String? _rebaseLocal(String? resolved) => resolved == null || id == null
      ? resolved
      : LocalCoverResolver.resolve(resolved, bookId: id);

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
      isBorrowed: isBorrowed,
      isLent: isLent,
      wanted: wanted,
    );
  }

  /// Returns star rating (1-5) from internal 0-10 scale
  double? get starRating => userRating != null ? userRating! / 2.0 : null;
}
