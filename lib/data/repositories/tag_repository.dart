import '../../models/tag.dart';

abstract class TagRepository {
  Future<List<Tag>> getTags();

  Future<Tag> createTag(String name, {int? parentId});

  Future<Tag> updateTag(int id, String name, {int? parentId});

  Future<void> deleteTag(int id);
}
