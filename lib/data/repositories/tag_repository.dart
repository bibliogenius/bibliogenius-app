import '../../models/tag.dart';

abstract class TagRepository {
  Future<List<Tag>> getTags();

  Future<Tag> createTag(String name, {String? parentId});

  /// Update a tag addressed by its uuid (cross-device identity). The parent id
  /// is the parent tag's uuid.
  Future<Tag> updateTag(String uuid, String name, {String? parentId});

  /// Delete a tag addressed by its uuid (cross-device identity).
  Future<void> deleteTag(String uuid);

  /// Delete a shelf as the user sees it: the `tags` row when there is one,
  /// and its name from every book's subjects either way. A synthetic shelf
  /// (no row, see [Tag.isPersisted]) has only the second half to do.
  Future<void> deleteShelf(Tag tag);
}
