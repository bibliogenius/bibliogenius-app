import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/repositories/copy_repository.dart';
import '../models/book.dart';
import '../providers/ownership_preference_provider.dart';
import '../widgets/ownership_after_status_sheet.dart';
import 'book_filters.dart';
import 'ownership_actions.dart';

/// Runs the possession question for a status change, end to end.
///
/// Decides whether to ask (see [statusChangeAsksAboutOwnership]), shows the
/// sheet, and applies what was answered: the copy for a claimed book, the
/// "declined once" mark, or the widened view. The three status-change paths
/// (book page with and without a date, card badge) share this so they cannot
/// drift apart.
///
/// Returns whether the status write that follows must carry `owned: true`.
/// The flag rides on that write rather than on its own, so the status and the
/// possession land together.
Future<bool> resolveOwnershipForStatusChange(
  BuildContext context, {
  required Book book,
  required String newStatus,
}) async {
  final bookId = book.id;
  if (bookId == null) return false;
  final prefs = context.read<OwnershipPreferenceProvider>();
  if (!statusChangeAsksAboutOwnership(
    book,
    newStatus,
    viewScope: prefs.scope,
  )) {
    return false;
  }

  final answer = await showOwnershipAfterStatusSheet(
    context,
    book: book,
    offerShowAll: prefs.hasDeclinedOwnership,
  );
  if (!context.mounted) return false;

  switch (answer) {
    case OwnershipAnswer.own:
      final copies = context.read<CopyRepository>();
      await claimOwnershipCopies(copies: copies, bookId: bookId);
      return true;
    case OwnershipAnswer.notOwned:
      await prefs.markOwnershipDeclined();
      return false;
    case OwnershipAnswer.showAll:
      await prefs.setScope(OwnershipScope.all);
      return false;
    case null:
      return false;
  }
}
