/// Book note model for reading annotations.
///
/// Each note is attached to a book and contains text content,
/// an optional page number, and timestamps.
library;

import '../src/rust/api/frb.dart' as frb;

class BookNote {
  final int id;
  final String bookId;
  final String content;
  final int? page;
  final String createdAt;
  final String updatedAt;

  const BookNote({
    required this.id,
    required this.bookId,
    required this.content,
    this.page,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BookNote.fromFrb(frb.FrbBookNote n) {
    return BookNote(
      id: n.id,
      bookId: n.bookId,
      content: n.content,
      page: n.page,
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
    );
  }

  /// Parse the ISO 8601 created_at timestamp.
  DateTime? get createdDateTime => DateTime.tryParse(createdAt);
}
