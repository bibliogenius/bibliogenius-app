import '../../models/tag.dart';

abstract class TagRepository {
  Future<List<Tag>> getTags();

  Future<Tag> createTag(String name, {int? parentId});

  /// Update a tag addressed by its uuid (cross-device identity). The integer
  /// parent id is unchanged.
  Future<Tag> updateTag(String uuid, String name, {int? parentId});

  /// Delete a tag addressed by its uuid (cross-device identity).
  Future<void> deleteTag(String uuid);
}
