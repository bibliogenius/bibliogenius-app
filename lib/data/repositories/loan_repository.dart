import '../../models/loan.dart';
import '../../models/copy.dart';

abstract class LoanRepository {
  Future<List<Loan>> getLoans({String? status, int? contactId});

  Future<Loan> createLoan(Map<String, dynamic> loanData);

  Future<void> returnLoan(int loanId);

  Future<List<Copy>> getBorrowedCopies();
}
