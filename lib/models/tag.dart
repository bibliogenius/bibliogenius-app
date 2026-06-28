class Tag {
  /// Cross-device stable identity (the tag's uuid). Empty for synthetic legacy
  /// (subject-derived) tags that have no `tags` row.
  final String id;

  /// Backwards-compatible alias: the uuid is now the primary [id].
  String get uuid => id;
  final String name;
  final String? parentId;
  final String path;
  final int count;
  final List<Tag> children;

  Tag({
    required this.id,
    required this.name,
    this.parentId,
    this.path = '',
    required this.count,
    this.children = const [],
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: (json['uuid'] ?? json['id'])?.toString() ?? '',
      name: json['name'] as String,
      parentId: json['parent_id']?.toString(),
      path: json['path'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      children:
          (json['children'] as List<dynamic>?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'path': path,
      'count': count,
    };
  }

  /// Get the full display path including this tag's name
  String get fullPath => path.isEmpty ? name : '$path > $name';

  /// Check if this is a root tag (no parent)
  bool get isRoot => parentId == null;

  /// Whether this tag is backed by a real `tags` row (has a uuid), as opposed
  /// to a synthetic subject-derived entry.
  bool get isPersisted => id.isNotEmpty;

  /// Create a copy with updated children (for tree building)
  Tag copyWithChildren(List<Tag> newChildren) {
    return Tag(
      id: id,
      name: name,
      parentId: parentId,
      path: path,
      count: count,
      children: newChildren,
    );
  }

  /// Get all descendant IDs (children, grandchildren, etc.) for this tag
  /// Requires a flat list of all tags to traverse the hierarchy
  static Set<String> getDescendantIds(String tagId, List<Tag> allTags) {
    final descendants = <String>{};
    void collectChildren(String parentId) {
      for (final tag in allTags) {
        if (tag.parentId == parentId && tag.id.isNotEmpty) {
          descendants.add(tag.id);
          collectChildren(tag.id);
        }
      }
    }

    collectChildren(tagId);
    return descendants;
  }

  /// Get all tag names (including descendants) that match the given tag
  /// Used for filtering books by tag with hierarchy support
  static Set<String> getTagNamesWithDescendants(Tag tag, List<Tag> allTags) {
    final names = <String>{
      tag.fullPath.toLowerCase(),
      tag.name.toLowerCase(), // Also include simple name for matching
    };
    final descendantIds = getDescendantIds(tag.id, allTags);
    for (final t in allTags) {
      if (descendantIds.contains(t.id)) {
        names.add(t.fullPath.toLowerCase());
        names.add(t.name.toLowerCase());
      }
    }
    return names;
  }

  /// Get aggregated book count (this tag + all descendants)
  static int getAggregatedCount(Tag tag, List<Tag> allTags) {
    int total = tag.count;
    final descendantIds = getDescendantIds(tag.id, allTags);
    for (final t in allTags) {
      if (descendantIds.contains(t.id)) {
        total += t.count;
      }
    }
    return total;
  }

  /// Get only root-level tags (no parent)
  static List<Tag> getRootTags(List<Tag> allTags) {
    return allTags.where((t) => t.parentId == null).toList();
  }

  /// Get direct children of a tag
  static List<Tag> getDirectChildren(String tagId, List<Tag> allTags) {
    return allTags.where((t) => t.parentId == tagId).toList();
  }
}
