class Copy {
  final int? id;
  final int bookId;
  final int libraryId;
  final String? acquisitionDate;
  final String? notes;
  final String status; // available, borrowed, wanted, lost
  final bool isTemporary;

  Copy({
    this.id,
    required this.bookId,
    required this.libraryId,
    this.acquisitionDate,
    this.notes,
    this.status = 'available',
    this.isTemporary = false,
  });

  factory Copy.fromJson(Map<String, dynamic> json) {
    return Copy(
      id: json['id'],
      bookId: json['book_id'],
      libraryId: json['library_id'],
      acquisitionDate: json['acquisition_date'],
      notes: json['notes'],
      status: json['status'] ?? 'available',
      isTemporary: json['is_temporary'] ?? false,
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
      'created_at': now,
      'updated_at': now,
    };
  }
}
