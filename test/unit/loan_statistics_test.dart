import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/loan.dart';
import 'package:bibliogenius/utils/loan_statistics.dart';

Loan _loan({
  required int id,
  required String loanDate,
  String? returnDate,
  String status = 'active',
}) => Loan(
  id: id,
  copyId: id,
  contactId: id,
  libraryId: 1,
  loanDate: loanDate,
  dueDate: loanDate,
  returnDate: returnDate,
  status: status,
  contactName: 'c',
  bookTitle: 'b',
);

void main() {
  group('LoanStatistics.fromLoans', () {
    test('empty list: everything zero, rates null', () {
      final s = LoanStatistics.fromLoans(const []);
      expect(s.total, 0);
      expect(s.active, 0);
      expect(s.returned, 0);
      expect(s.returnRatePercent, isNull);
      expect(s.avgDurationDays, isNull);
    });

    test('only active loans: returnRate and avgDuration are null, not 0', () {
      // Regression: showing "0 %" / "0 j" on a library that never returned
      // anything was misleading. The correct signal is "no data yet".
      final s = LoanStatistics.fromLoans([
        _loan(id: 1, loanDate: '2026-04-01'),
        _loan(id: 2, loanDate: '2026-04-02'),
      ]);
      expect(s.total, 2);
      expect(s.active, 2);
      expect(s.returned, 0);
      expect(s.returnRatePercent, isNull);
      expect(s.avgDurationDays, isNull);
    });

    test('mixed loans: return rate computed correctly', () {
      final s = LoanStatistics.fromLoans([
        _loan(id: 1, loanDate: '2026-04-01'),
        _loan(
          id: 2,
          loanDate: '2026-04-01',
          returnDate: '2026-04-11',
          status: 'returned',
        ),
        _loan(
          id: 3,
          loanDate: '2026-04-01',
          returnDate: '2026-04-06',
          status: 'returned',
        ),
      ]);
      expect(s.total, 3);
      expect(s.active, 1);
      expect(s.returned, 2);
      expect(s.returnRatePercent, closeTo(66.66, 0.1));
      // (10 + 5) / 2 = 7.5 days
      expect(s.avgDurationDays, closeTo(7.5, 0.01));
    });

    test('same-day returns contribute fractional days (not truncated to 0)', () {
      // Regression: DateTime.difference().inDays truncates; a loan returned
      // 12 hours later used to count as 0 days, dragging the average down to
      // an unhelpful "0 j" for libraries with short loans.
      final s = LoanStatistics.fromLoans([
        _loan(
          id: 1,
          loanDate: '2026-04-01T08:00:00Z',
          returnDate: '2026-04-01T20:00:00Z',
          status: 'returned',
        ),
      ]);
      expect(s.avgDurationDays, closeTo(0.5, 0.01));
    });

    test('unparseable dates are skipped silently', () {
      final s = LoanStatistics.fromLoans([
        _loan(
          id: 1,
          loanDate: 'not-a-date',
          returnDate: '2026-04-01',
          status: 'returned',
        ),
        _loan(
          id: 2,
          loanDate: '2026-04-01',
          returnDate: '2026-04-03',
          status: 'returned',
        ),
      ]);
      expect(s.returned, 2);
      expect(s.avgDurationDays, closeTo(2, 0.01));
    });

    test('returnDate == null is treated as active regardless of status', () {
      final s = LoanStatistics.fromLoans([
        _loan(id: 1, loanDate: '2026-04-01', status: 'returned'),
      ]);
      expect(s.active, 1);
      expect(s.returned, 0);
      expect(s.returnRatePercent, isNull);
    });
  });

  group('formatReturnRate', () {
    test('null renders as placeholder', () {
      expect(formatReturnRate(null), statMissingPlaceholder);
    });

    test('rounds to integer percent', () {
      expect(formatReturnRate(93.94), '94 %');
      expect(formatReturnRate(0.4), '0 %');
      expect(formatReturnRate(100), '100 %');
    });
  });

  group('formatAvgDuration', () {
    test('null renders as placeholder', () {
      expect(
        formatAvgDuration(null, lessThanOneDayLabel: '< 1 j'),
        statMissingPlaceholder,
      );
    });

    test('sub-day average renders as the provided less-than label', () {
      expect(
        formatAvgDuration(0.65, lessThanOneDayLabel: '< 1 j'),
        '< 1 j',
      );
      expect(
        formatAvgDuration(0.0001, lessThanOneDayLabel: '< 1 j'),
        '< 1 j',
      );
    });

    test('>= 1 day rounds to integer with unit suffix', () {
      expect(formatAvgDuration(1.0, lessThanOneDayLabel: '< 1 j'), '1 j');
      expect(formatAvgDuration(4.3, lessThanOneDayLabel: '< 1 j'), '4 j');
      expect(formatAvgDuration(29.8, lessThanOneDayLabel: '< 1 j'), '30 j');
    });
  });
}
