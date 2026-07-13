import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';

/// Turns a genre picked from the closed list into an ordinary shelf, creating
/// rows only when they are actually needed.
///
/// Nothing is created until a genre is picked: a user who ignores the feature
/// keeps a tag tree with no "Genre" shelf in it.
class GenreTagService {
  final TagRepository _tags;

  GenreTagService(this._tags);

  /// Ensure the shelf chain [labels] exists (outermost first, e.g.
  /// `["Genre", "Polar", "Thriller"]`) and return the leaf.
  ///
  /// Each level is resolved by name before being created. This is not an
  /// optimisation: `tags.name` is UNIQUE across the whole tree, so blindly
  /// creating "Polar" under "Genre" for a user who already keeps a "Polar"
  /// shelf would fail the constraint. An existing shelf is reused where it
  /// stands and is never re-parented: the user curated it, we do not move it.
  ///
  /// Only the ancestors that actually end up parenting something are created.
  /// Filing a book under a "Polar" shelf the user already keeps at the root
  /// creates no "Genre" shelf at all, rather than an empty one next to it.
  Future<Tag> resolveShelfChain(List<String> labels) async {
    var known = await _tags.getTags();

    final leaf = _findByName(known, labels.last);
    if (leaf != null && leaf.isPersisted) return leaf;

    // Walk up from the leaf's parent to the root and stop at the first shelf
    // that already exists: everything above it is already in place, and
    // everything below it is what we owe.
    final missing = <String>[];
    Tag? anchor;

    for (var i = labels.length - 2; i >= 0; i--) {
      final existing = _findByName(known, labels[i]);
      if (existing != null && existing.isPersisted) {
        anchor = existing;
        break;
      }
      missing.insert(0, labels[i]);
    }

    var parent = anchor;
    // The leaf is either absent, or a synthetic entry derived from a book's
    // subjects with no `tags` row behind it. Both are free to insert: the
    // UNIQUE constraint is on the table, not on the subject strings.
    for (final label in [...missing, labels.last]) {
      final created = await _tags.createTag(label, parentId: parent?.id);
      known = [...known, created];
      parent = created;
    }

    return parent!;
  }

  static Tag? _findByName(List<Tag> tags, String name) {
    final target = name.trim().toLowerCase();
    for (final tag in tags) {
      if (tag.name.trim().toLowerCase() == target) return tag;
    }
    return null;
  }
}
