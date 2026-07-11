/// Builds the `POST /api/copies` body for a book borrowed from a contact.
///
/// Writer counterpart of [BorrowedCopyDisplay] (`borrowed_copy_display.dart`):
/// after ADR-034 the lender and the due date live in typed columns, so `notes`
/// stays free for the user. New code must never encode the lender into `notes`,
/// which would force the reader back onto its legacy regex fallback.
///
/// `is_temporary` stays false. The flag scopes the P2P queries alongside
/// `borrow_source = 'peer'` (see `find_peer_borrowed_copy` in `api/peer.rs`);
/// what makes a copy show up in the borrowed list is its `status`.
///
/// Kept as a pure function so both borrow entry points build the same row and
/// so the shape can be unit-tested without a widget tree.
Map<String, dynamic> contactLoanCopyPayload({
  required String bookId,
  required String lenderDisplayName,
  String? acquisitionDate,
  String? borrowDueDate,
}) {
  return {
    'book_id': bookId,
    // library_id resolved by the backend
    'status': 'borrowed',
    'is_temporary': false,
    'borrow_source': 'contact',
    'lender_display_name': lenderDisplayName,
    if (acquisitionDate != null) 'acquisition_date': acquisitionDate,
    if (borrowDueDate != null) 'borrow_due_date': borrowDueDate,
  };
}
