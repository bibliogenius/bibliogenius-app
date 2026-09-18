import '../../models/tag.dart';
import '../../services/api_service.dart';
import '../repositories/tag_repository.dart';

class TagRepositoryImpl implements TagRepository {
  final ApiService _apiService;

  TagRepositoryImpl(this._apiService);

  @override
  Future<List<Tag>> getTags() {
    return _apiService.getTags();
  }

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
