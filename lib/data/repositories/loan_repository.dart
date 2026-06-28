import '../../models/loan.dart';
import '../../models/copy.dart';

abstract class LoanRepository {
  Future<List<Loan>> getLoans({String? status, int? contactId});

  Future<Loan> createLoan(Map<String, dynamic> loanData);

  /// Return a loan addressed by its uuid (cross-device identity).
  Future<void> returnLoan(String uuid);

  Future<List<Copy>> getBorrowedCopies();
}
