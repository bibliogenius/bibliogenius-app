import '../../models/copy.dart';

abstract class CopyRepository {
  Future<List<Copy>> getBookCopies(int bookId);

  Future<Copy> getCopy(int copyId);

  Future<Copy> createCopy(Map<String, dynamic> copyData);

  Future<Copy> updateCopy(int copyId, Map<String, dynamic> data);

  Future<void> deleteCopy(int copyId);
}
