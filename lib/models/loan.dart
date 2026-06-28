import '../utils/cover_url_resolver.dart';
import '../utils/local_cover_resolver.dart';

class Loan {
  /// Cross-device stable identity (the loan's uuid). Backend-owned; null for
  /// transient loans or rows not yet persisted. Addresses a loan over FFI
  /// (return).
  final String? id;

  /// Backwards-compatible alias: the uuid is now the primary [id].
  String? get uuid => id;

  final String copyId;
  final String contactId;
  final int libraryId;
  final String loanDate;
  final String dueDate;
  final String? returnDate;
  final String status;
  final String? notes;
  final String contactName;
  final String bookTitle;
  final String? bookId;
  final String? coverUrl;
  final String? isbn;

  Loan({
    this.id,
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
      // Identity is the uuid, carried under `uuid` or (post-flip) `id`.
      id: (json['uuid'] ?? json['id'])?.toString(),
      copyId: json['copy_id'].toString(),
      contactId: json['contact_id'].toString(),
      libraryId: json['library_id'] as int,
      loanDate: json['loan_date'] as String,
      dueDate: json['due_date'] as String,
      returnDate: json['return_date'] as String?,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      contactName: json['contact_name'] as String? ?? '',
      bookTitle: json['book_title'] as String? ?? '',
      bookId: json['book_id']?.toString(),
      coverUrl: json['cover_url'] as String?,
      isbn: json['isbn'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // The uuid is the identity; `Loan.fromJson` reads `uuid ?? id`.
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
