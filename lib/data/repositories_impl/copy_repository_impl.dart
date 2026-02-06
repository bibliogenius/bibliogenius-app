import '../../models/copy.dart';
import '../../services/api_service.dart';
import '../repositories/copy_repository.dart';

class CopyRepositoryImpl implements CopyRepository {
  final ApiService _apiService;

  CopyRepositoryImpl(this._apiService);

  @override
  Future<List<Copy>> getBookCopies(int bookId) async {
    final response = await _apiService.getBookCopies(bookId);
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      List<dynamic> copies;
      if (data is Map && data['copies'] is List) {
        copies = data['copies'] as List;
      } else if (data is List) {
        copies = data;
      } else {
        return [];
      }
      return copies
          .map((json) => Copy.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<Copy> getCopy(int copyId) async {
    final response = await _apiService.getCopy(copyId);
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return Copy.fromJson(data);
      }
    }
    throw Exception('Copy not found');
  }

  @override
  Future<Copy> createCopy(Map<String, dynamic> copyData) async {
    final response = await _apiService.createCopy(copyData);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return Copy.fromJson(data);
      }
    }
    throw Exception('Failed to create copy (status: ${response.statusCode})');
  }

  @override
  Future<Copy> updateCopy(int copyId, Map<String, dynamic> data) async {
    final response = await _apiService.updateCopy(copyId, data);
    if (response.statusCode == 200 && response.data != null) {
      final responseData = response.data;
      if (responseData is Map<String, dynamic>) {
        return Copy.fromJson(responseData);
      }
    }
    throw Exception('Failed to update copy (status: ${response.statusCode})');
  }

  @override
  Future<void> deleteCopy(int copyId) async {
    final response = await _apiService.deleteCopy(copyId);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to delete copy (status: ${response.statusCode})',
      );
    }
  }
}
