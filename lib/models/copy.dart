class Copy {
  final String? id;
  final String bookId;
  final int libraryId;
  final String? acquisitionDate;
  final String? notes;
  final String status; // available, borrowed, wanted, lost
  final bool isTemporary;
  final double? price; // Copy-specific price (overrides book price)

  /// ADR-034 loan metadata. All four are only populated for borrowed copies.
  final String? lenderDisplayName;
  final int? lenderPeerId;
  final String? borrowDueDate;
  final String? borrowSource; // 'peer' or 'contact'

  Copy({
    this.id,
    required this.bookId,
    required this.libraryId,
    this.acquisitionDate,
    this.notes,
    this.status = 'available',
    this.isTemporary = false,
    this.price,
    this.lenderDisplayName,
    this.lenderPeerId,
    this.borrowDueDate,
    this.borrowSource,
  });

  factory Copy.fromJson(Map<String, dynamic> json) {
    return Copy(
      id: json['id']?.toString(),
      bookId: json['book_id'].toString(),
      libraryId: json['library_id'],
      acquisitionDate: json['acquisition_date'],
      notes: json['notes'],
      status: json['status'] ?? 'available',
      isTemporary: json['is_temporary'] ?? false,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      lenderDisplayName: json['lender_display_name'],
      lenderPeerId: json['lender_peer_id'],
      borrowDueDate: json['borrow_due_date'],
      borrowSource: json['borrow_source'],
    );
  }

  Map<String, dynamic> toJson() {
    final now = DateTime.now().toIso8601String();
    return {
      'book_id': bookId,
      'library_id': libraryId,
      'acquisition_date': acquisitionDate,
      'notes': notes,
      'status': status,
      'is_temporary': isTemporary,
      'price': price,
      'lender_display_name': lenderDisplayName,
      'lender_peer_id': lenderPeerId,
      'borrow_due_date': borrowDueDate,
      'borrow_source': borrowSource,
      'created_at': now,
      'updated_at': now,
    };
  }
}
