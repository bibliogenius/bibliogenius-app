import 'package:flutter/foundation.dart';

import '../data/repositories/copy_repository.dart';
import '../models/book.dart';
import 'book_filters.dart';

/// What applying an ownership change did to the book's copies.
class OwnershipChangeResult {
  const OwnershipChangeResult({
    required this.copyId,
    required this.copiesDeleted,
    required this.hadFailures,
  });

  /// The copy the book now has, when it is owned; null when it is not.
  final String? copyId;

  /// How many copies were removed by releasing ownership.
  final int copiesDeleted;

  /// A deletion threw. The flag exists because the two callers want opposite
  /// things: the edit form has always swallowed this into a debug line, while
  /// a page that just asked the reader to confirm a destructive change owes
  /// them a word when it did not happen.
  final bool hadFailures;
}

/// Applies the copy-side consequences of the `owned` flag.
///
/// Ownership is not only a column: a book that stops being owned loses its
/// copies, and one that starts being owned needs one, or it would claim to be
/// on the shelf while offering nothing to lend and advertising zero available
/// copies to peers.
///
/// This lived inline in the edit form's save path. It is shared now because
/// the book page reaches the same flag from its own menu, and two
/// implementations of a rule that deletes rows and orphans loans is one too
/// many.
///
/// Callers are responsible for the guard: releasing ownership while a copy is
/// lent or borrowed destroys the row a live loan points at. This function
/// deliberately does not decide that, because the two callers phrase the
/// refusal differently.
Future<OwnershipChangeResult> applyOwnershipToCopies({
  required CopyRepository copies,
  required String bookId,
  required bool owned,
  String? existingCopyId,
  String copyStatus = 'available',
}) async {
  if (!owned) {
    var deleted = 0;
    var failed = false;
    try {
      final existing = await copies.getBookCopies(bookId);
      for (final copy in existing) {
        final id = copy.id;
        if (id == null) continue;
        await copies.deleteCopy(id);
        deleted++;
      }
    } catch (e) {
      failed = true;
      debugPrint('Error cleaning up copies for un-owned book: $e');
    }
    return OwnershipChangeResult(
      copyId: null,
      copiesDeleted: deleted,
      hadFailures: failed,
    );
  }

  if (existingCopyId != null) {
    await copies.updateCopy(existingCopyId, {'status': copyStatus});
    return OwnershipChangeResult(
      copyId: existingCopyId,
      copiesDeleted: 0,
      hadFailures: false,
    );
  }

  final created = await copies.createCopy({
    'book_id': bookId,
    'status': copyStatus,
  });
  return OwnershipChangeResult(
    copyId: created.id,
    copiesDeleted: 0,
    hadFailures: false,
  );
}

/// Whether giving [book] the reading status [newStatus] should ask the reader
/// about possession.
///
/// The default library view shows what the reader physically has (ADR-063),
/// and a reading status never changes `owned`. So a wish marked "read" from
/// the status picker stayed `owned = false`, reachable under "Read" but gone
/// from "All my books", and the reader saw a book vanish. Acquisition already
/// asks the mirror question ("I bought it" clears the wish); this is the
/// other direction.
///
/// A book on loan is not asked: a borrowed copy is someone else's, and the
/// return flow owns that answer. A wish stays a wish, unasked. And when the
/// remembered [viewScope] already shows everything, nothing can disappear,
/// so there is nothing to ask.
bool statusChangeAsksAboutOwnership(
  Book book,
  String newStatus, {
  String? viewScope,
}) {
  if (viewScope == OwnershipScope.all) return false;
  if (book.owned || book.isOnLoan) return false;
  return newStatus != 'wanting';
}

/// Possession claimed while changing a reading status.
///
/// The book had no copy on record (neither owned nor on loan), so one is
/// created. A stray row is reused rather than doubled, the same way the book
/// page does it when it knows its copies already.
Future<OwnershipChangeResult> claimOwnershipCopies({
  required CopyRepository copies,
  required String bookId,
}) async {
  final existing = await copies.getBookCopies(bookId);
  final stray = existing.isNotEmpty ? existing.first.id : null;
  return applyOwnershipToCopies(
    copies: copies,
    bookId: bookId,
    owned: true,
    existingCopyId: stray,
  );
}
