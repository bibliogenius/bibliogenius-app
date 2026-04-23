/// Resolves the lender name and due date that a borrowed-copy tile should
/// display, whichever format the backend returned.
///
/// After ADR-034, `/api/copies/borrowed` exposes typed columns
/// (`lender_display_name`, `borrow_due_date`). Pre-034 rows whose
/// migration-075 backfill could not match the legacy free-text `notes`
/// format still need to render, so we keep the old regex as a fallback.
///
/// Kept as a pure function so it can be unit-tested without bringing up
/// the widget tree.
class BorrowedCopyDisplay {
  final String lenderName;
  final String dueDate;

  const BorrowedCopyDisplay({this.lenderName = '', this.dueDate = ''});

  factory BorrowedCopyDisplay.fromBookMap(Map<String, dynamic> book) {
    var name = (book['lender_display_name'] as String?) ?? '';
    var due = (book['borrow_due_date'] as String?) ?? '';
    final notes = (book['notes'] as String?) ?? '';

    if (name.isEmpty && notes.isNotEmpty) {
      final m = RegExp(
        r"(?:Emprunté de|Borrowed from|Emprunté à)[:\s]*(.+?)(?:\s+jusqu|$)",
      ).firstMatch(notes);
      if (m != null) {
        name = m.group(1)?.trim() ?? '';
      }
    }
    if (due.isEmpty && notes.isNotEmpty) {
      final m = RegExp(r"jusqu'au\s+(\S+)").firstMatch(notes);
      if (m != null) {
        due = m.group(1)?.trim() ?? '';
      }
    }

    return BorrowedCopyDisplay(lenderName: name, dueDate: due);
  }
}
