import '../../models/copy.dart';
import '../../models/loan.dart';
import '../../services/api_service.dart';
import '../repositories/loan_repository.dart';

class LoanRepositoryImpl implements LoanRepository {
  final ApiService _apiService;

  LoanRepositoryImpl(this._apiService);

  @override
  Future<List<Loan>> getLoans({String? status, int? contactId}) async {
    final response = await _apiService.getLoans(
      status: status,
      contactId: contactId,
    );
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data is Map && data['loans'] is List) {
        return (data['loans'] as List)
            .map((json) => Loan.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  @override
  Future<Loan> createLoan(Map<String, dynamic> loanData) async {
    final response = await _apiService.createLoan(loanData);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = response.data;
      if (data is Map && data['loan'] is Map) {
        final loanJson = data['loan'] as Map<String, dynamic>;
        // createLoan may return minimal data (just {id}), construct a partial
        // Loan. The integer id is the transitional localId; uuid follows at S4.
        return Loan(
          localId: loanJson['id'] as int?,
          copyId: loanData['copy_id'] as int,
          contactId: loanData['contact_id'] as int,
          libraryId: loanData['library_id'] as int? ?? 0,
          loanDate: loanData['loan_date'] as String,
          dueDate: loanData['due_date'] as String,
          notes: loanData['notes'] as String?,
          status: 'active',
          contactName: '',
          bookTitle: '',
        );
      }
    }
    throw Exception('Failed to create loan (status: ${response.statusCode})');
  }

  @override
  Future<void> returnLoan(String uuid) async {
    final response = await _apiService.returnLoan(uuid);
    if (response.statusCode != 200) {
      throw Exception('Failed to return loan (status: ${response.statusCode})');
    }
  }

  @override
  Future<List<Copy>> getBorrowedCopies() async {
    final response = await _apiService.getBorrowedCopies();
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      List<dynamic> items;
      if (data is Map && data['loans'] is List) {
        items = data['loans'] as List;
      } else if (data is List) {
        items = data;
      } else {
        return [];
      }
      return items.map((json) {
        final map = Map<String, dynamic>.from(json as Map);
        // Backend `/api/copies/borrowed` omits library_id; inject a default so
        // Copy.fromJson's `required int libraryId` does not throw on null.
        map.putIfAbsent('library_id', () => 0);
        return Copy.fromJson(map);
      }).toList();
    }
    return [];
  }
}
