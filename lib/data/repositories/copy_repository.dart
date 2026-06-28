import '../../models/copy.dart';

abstract class CopyRepository {
  Future<List<Copy>> getBookCopies(String bookId);

  Future<Copy> getCopy(String copyId);

  Future<Copy> createCopy(Map<String, dynamic> copyData);

  Future<Copy> updateCopy(String copyId, Map<String, dynamic> data);

  Future<void> deleteCopy(String copyId);
}
