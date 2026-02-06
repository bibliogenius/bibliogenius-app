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
  Future<Tag> createTag(String name, {int? parentId}) {
    return _apiService.createTag(name, parentId: parentId);
  }

  @override
  Future<Tag> updateTag(int id, String name, {int? parentId}) {
    return _apiService.updateTag(id, name, parentId: parentId);
  }

  @override
  Future<void> deleteTag(int id) {
    return _apiService.deleteTag(id);
  }
}
