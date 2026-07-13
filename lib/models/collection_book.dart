class CollectionBook {
  final String bookId;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? publisher;
  final int? publicationYear;
  final DateTime addedAt;
  final bool isOwned;

  /// Personal reading status (`to_read`, `reading`, `read`, `wanting`,
  /// `abandoned`). Drives the "unread = dimmed" rendering of the series frise.
  final String? readingStatus;

  /// Reading-order position within a series-typed collection. `null` for
  /// unnumbered members (rendered after the numbered ones).
  final int? volumeNumber;

  CollectionBook({
    required this.bookId,
    required this.title,
    this.author,
    this.coverUrl,
    this.publisher,
    this.publicationYear,
    required this.addedAt,
    required this.isOwned,
    this.readingStatus,
    this.volumeNumber,
  });

  /// Whether this volume counts as read (drives frise opacity). Only a finished
  /// read is treated as read; every other status renders dimmed.
  bool get isRead => readingStatus == 'read';

  CollectionBook copyWith({int? volumeNumber}) {
    return CollectionBook(
      bookId: bookId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      publisher: publisher,
      publicationYear: publicationYear,
      addedAt: addedAt,
      isOwned: isOwned,
      readingStatus: readingStatus,
      volumeNumber: volumeNumber ?? this.volumeNumber,
    );
  }

  factory CollectionBook.fromJson(Map<String, dynamic> json) {
    return CollectionBook(
      bookId: json['book_id'].toString(),
      title: json['title'],
      author: json['author'],
      coverUrl: json['cover_url'],
      publisher: json['publisher'],
      publicationYear: json['publication_year'],
      addedAt: DateTime.parse(json['added_at']),
      isOwned: json['is_owned'] ?? false,
      readingStatus: json['reading_status'],
      volumeNumber: json['volume_number'],
    );
  }
}
