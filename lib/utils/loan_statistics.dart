import '../models/loan.dart';

/// Aggregated loan metrics computed from a list of [Loan]s.
///
/// [returnRatePercent] and [avgDurationDays] are `null` when no returned loan
/// is available to compute them (vs. `0` which would falsely suggest a
/// measured zero). Call sites render these with the `-` placeholder.
class LoanStatistics {
  final int total;
  final int active;
  final int returned;
  final double? returnRatePercent;
  final double? avgDurationDays;

  const LoanStatistics({
    required this.total,
    required this.active,
    required this.returned,
    required this.returnRatePercent,
    required this.avgDurationDays,
  });

  factory LoanStatistics.fromLoans(Iterable<Loan> loans) {
    final list = loans.toList(growable: false);
    final total = list.length;
    final returnedList = list.where((l) => l.returnDate != null).toList();
    final returned = returnedList.length;
    final active = total - returned;

    double? returnRate;
    if (total > 0 && returned > 0) {
      returnRate = returned / total * 100;
    }

    double? avgDuration;
    if (returnedList.isNotEmpty) {
      double totalMinutes = 0;
      int counted = 0;
      for (final loan in returnedList) {
        final loanDate = DateTime.tryParse(loan.loanDate);
        final returnDate = DateTime.tryParse(loan.returnDate!);
        if (loanDate == null || returnDate == null) continue;
        final diffMinutes = returnDate.difference(loanDate).inMinutes.abs();
        totalMinutes += diffMinutes;
        counted++;
      }
      if (counted > 0) {
        avgDuration = totalMinutes / counted / (60 * 24);
      }
    }

    return LoanStatistics(
      total: total,
      active: active,
      returned: returned,
      returnRatePercent: returnRate,
      avgDurationDays: avgDuration,
    );
  }
}

/// Placeholder shown when a metric cannot be computed (no data yet).
const String statMissingPlaceholder = '-';

/// Format a return rate for display in a mini-stat card.
///
/// Returns [statMissingPlaceholder] when [rate] is null (no returned loans),
/// otherwise a rounded integer percentage with a `%` suffix.
String formatReturnRate(double? rate) {
  if (rate == null) return statMissingPlaceholder;
  return '${rate.round()} %';
}

/// Format an average loan duration for display.
///
/// - `null` (no returned loan) renders as [statMissingPlaceholder].
/// - Sub-day averages render as [lessThanOneDayLabel] (e.g. "< 1 j") to avoid
///   the misleading "0 j" produced by integer truncation on same-day returns.
/// - Otherwise a rounded integer followed by [unitSuffix] (e.g. "4 j").
String formatAvgDuration(
  double? days, {
  required String lessThanOneDayLabel,
  String unitSuffix = 'j',
}) {
  if (days == null) return statMissingPlaceholder;
  if (days < 1) return lessThanOneDayLabel;
  return '${days.round()} $unitSuffix';
}
