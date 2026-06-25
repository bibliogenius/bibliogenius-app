import '../utils/cover_url_resolver.dart';
import '../utils/local_cover_resolver.dart';

class Loan {
  final int id;

  /// Stable cross-device identifier (ST-03). Backend-owned, read-only client side.
  final String? uuid;
  final int copyId;
  final int contactId;
  final int libraryId;
  final String loanDate;
  final String dueDate;
  final String? returnDate;
  final String status;
  final String? notes;
  final String contactName;
  final String bookTitle;
  final int? bookId;
  final String? coverUrl;
  final String? isbn;

  Loan({
    required this.id,
    this.uuid,
    required this.copyId,
    required this.contactId,
    required this.libraryId,
    required this.loanDate,
    required this.dueDate,
    this.returnDate,
    required this.status,
    this.notes,
    required this.contactName,
    required this.bookTitle,
    this.bookId,
    this.coverUrl,
    this.isbn,
  });

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as int,
      uuid: json['uuid'] as String?,
      copyId: json['copy_id'] as int,
      contactId: json['contact_id'] as int,
      libraryId: json['library_id'] as int,
      loanDate: json['loan_date'] as String,
      dueDate: json['due_date'] as String,
      returnDate: json['return_date'] as String?,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      contactName: json['contact_name'] as String? ?? '',
      bookTitle: json['book_title'] as String? ?? '',
      bookId: json['book_id'] as int?,
      coverUrl: json['cover_url'] as String?,
      isbn: json['isbn'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'copy_id': copyId,
      'contact_id': contactId,
      'library_id': libraryId,
      'loan_date': loanDate,
      'due_date': dueDate,
      'return_date': returnDate,
      'status': status,
      'notes': notes,
      'contact_name': contactName,
      'book_title': bookTitle,
      'book_id': bookId,
    };
  }

  bool get isActive => status == 'active';
  bool get isReturned => returnDate != null || status == 'returned';

  /// Resolved cover URL: explicit cover_url, or OpenLibrary fallback from ISBN.
  /// A local cover path is re-based onto the current covers directory keyed by
  /// [bookId] (iOS data-container UUID drift; see [LocalCoverResolver]).
  String? get resolvedCoverUrl {
    final resolved =
        CoverUrlResolver.resolveForLocal(coverUrl: coverUrl, isbn: isbn);
    return resolved == null || bookId == null
        ? resolved
        : LocalCoverResolver.resolve(resolved, bookId: bookId);
  }
}
