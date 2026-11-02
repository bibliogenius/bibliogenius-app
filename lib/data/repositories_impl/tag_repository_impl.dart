import '../../models/tag.dart';
import '../../services/api_service.dart';
import '../repositories/tag_repository.dart';

class TagRepositoryImpl implements TagRepository {
  final ApiService _apiService;

  TagRepositoryImpl(this._apiService);

  /// Every shelf, in the one order the app lists shelves in
  /// ([compareShelves]): the core sorts by raw bytes, which puts "Zola"
  /// before "écrits".
  @override
  Future<List<Tag>> getTags() async {
    final tags = await _apiService.getTags();
    return [...tags]..sort(compareShelves);
  }

  @override
  Future<int> countUnshelvedBooks() => _apiService.countUnshelvedBooks();

  @override
  Future<Tag> createTag(String name, {String? parentId}) {
    return _apiService.createTag(name, parentId: parentId);
  }

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) {
    return _apiService.updateTag(uuid, name, parentId: parentId);
  }

  @override
  Future<void> deleteTag(String uuid) {
    return _apiService.deleteTag(uuid);
  }

  @override
  Future<void> deleteShelf(Tag tag) {
    // The backend strips the name from the books when it deletes the row;
    // a synthetic shelf has no row, so only the books are left to clean.
    if (tag.isPersisted) return _apiService.deleteTag(tag.uuid);
    return _apiService.removeSubject(tag.name);
  }
}
