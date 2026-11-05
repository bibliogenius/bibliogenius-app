import '../utils/book_filters.dart';

class Tag {
  /// Cross-device stable identity (the tag's uuid). Empty for synthetic legacy
  /// (subject-derived) tags that have no `tags` row.
  final String id;

  /// Backwards-compatible alias: the uuid is now the primary [id].
  String get uuid => id;
  final String name;
  final String? parentId;
  final String path;

  /// Books on this shelf that the DEFAULT library view shows.
  final int count;

  /// Books on this shelf whatever their ownership.
  ///
  /// Differs from [count] as soon as the shelf holds wished or given-away
  /// books. Which of the two a badge should print depends on the reader's
  /// remembered ownership axis (ADR-063), so both travel and the caller
  /// picks: see `countForOwnershipScope`.
  final int totalCount;
  final List<Tag> children;

  /// Up to three covers for the shelf's thumbnail, newest first, sub-shelves
  /// included, from the default library view. Already resolved by the core:
  /// a file of this device or a URL, ready for `CachedBookCover`.
  final List<String> coverPaths;

  /// [count] with the sub-shelves, worked out by the core so that a book on a
  /// shelf and on its sub-shelf counts once. Null on a tag from no listing, and
  /// above a shelf waiting on its Undo (see [withoutShelves]).
  final int? subtreeCount;

  /// [totalCount] with the sub-shelves, likewise.
  final int? subtreeTotalCount;

  Tag({
    required this.id,
    required this.name,
    this.parentId,
    this.path = '',
    required this.count,
    int? totalCount,
    this.children = const [],
    this.coverPaths = const [],
    this.subtreeCount,
    this.subtreeTotalCount,
  }) : totalCount = totalCount ?? count;

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: (json['uuid'] ?? json['id'])?.toString() ?? '',
      name: json['name'] as String,
      parentId: json['parent_id']?.toString(),
      path: json['path'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      totalCount: json['total_count'] as int?,
      // `GET /api/books/tags` names them by what they are over HTTP: URLs.
      coverPaths: [
        for (final cover in json['cover_urls'] as List? ?? [])
          cover.toString(),
      ],
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
      'total_count': totalCount,
    };
  }

  /// Get the full display path including this tag's name
  String get fullPath => path.isEmpty ? name : '$path > $name';

  /// Check if this is a root tag (no parent)
  bool get isRoot => parentId == null;

  /// Prefix of the ids the FFI listing gives synthetic entries (`legacy:-1`,
  /// `legacy:-2`, ...): a name found in the books' subjects with no `tags`
  /// row behind it. The HTTP listing spells the same absence as an empty id.
  static const syntheticIdPrefix = 'legacy:';

  /// Whether this tag is backed by a real `tags` row (has a uuid), as opposed
  /// to a synthetic subject-derived entry.
  ///
  /// Both spellings of "no row" count: a `legacy:` id used to pass here as
  /// persisted, so filing a book under a genre whose name survived as an
  /// orphan created neither the genre nor its parents.
  bool get isPersisted => id.isNotEmpty && !id.startsWith(syntheticIdPrefix);

  /// What tells this shelf apart from one listing to the next: a shelf with a
  /// row by its id, one known only from the books' subjects by its name. The
  /// core numbers those `legacy:` ids afresh, in no stable order, on every
  /// listing, and over HTTP their id is empty.
  String get stableKey => isPersisted ? id : 'name:$name';

  /// This shelf under another name, everything else as listed.
  Tag renamed(String newName) => Tag(
    id: id,
    name: newName,
    parentId: parentId,
    path: path,
    count: count,
    totalCount: totalCount,
    children: children,
    coverPaths: coverPaths,
    subtreeCount: subtreeCount,
    subtreeTotalCount: subtreeTotalCount,
  );

  /// Create a copy with updated children (for tree building)
  Tag copyWithChildren(List<Tag> newChildren) {
    return Tag(
      id: id,
      name: name,
      parentId: parentId,
      path: path,
      count: count,
      totalCount: totalCount,
      children: newChildren,
      coverPaths: coverPaths,
      subtreeCount: subtreeCount,
      subtreeTotalCount: subtreeTotalCount,
    );
  }

  /// The parent this tag is shown under, or null for the first level.
  ///
  /// Sync can bring a tree the app would never write: a shelf whose parent
  /// row is gone, or a cycle (two devices moving shelves concurrently). Such
  /// a shelf must neither vanish from the tree nor send a walk round forever,
  /// so a missing parent, and any shelf caught in a cycle, read as first
  /// level. A shelf merely hanging below a cycle keeps its own parent. Every
  /// tree helper goes through this, never through [parentId] directly.
  static String? effectiveParentId(Tag tag, List<Tag> allTags) =>
      _effectiveParentIn(tag, _parentIndex(allTags));

  /// Effective parent of every tag in [allTags], keyed by id.
  static Map<String, String?> effectiveParentIds(List<Tag> allTags) =>
      _treeIndexOf(allTags).parents;

  /// The shelves above [tag] in [allTags], from the first level down to its
  /// parent. A cycle merged from sync ends the climb where it comes back.
  static List<Tag> ancestorsOf(Tag tag, List<Tag> allTags) {
    final parents = effectiveParentIds(allTags);
    final byId = {for (final t in allTags) t.id: t};
    final seen = <String>{tag.id};
    final ancestors = <Tag>[];
    var id = parents[tag.id];
    while (id != null && seen.add(id)) {
      final parent = byId[id];
      if (parent == null) break;
      ancestors.insert(0, parent);
      id = parents[id];
    }
    return ancestors;
  }

  /// [allTags] without the shelves of [ids], each of their sub-shelves shown
  /// where deleting them puts it: under the removed shelf's own parent, or
  /// that one's when it is removed too. Tags left in place are the same
  /// instances; [allTags] itself when there is nothing to remove.
  static List<Tag> withoutShelves(List<Tag> allTags, Set<String> ids) {
    if (ids.isEmpty) return allTags;
    final parents = effectiveParentIds(allTags);
    String? shownParent(String? id) {
      final seen = <String>{};
      while (id != null && ids.contains(id) && seen.add(id)) {
        id = parents[id];
      }
      return id != null && ids.contains(id) ? null : id;
    }

    // Above a removed shelf the core's count still holds its books, and only
    // the core could say which of them are elsewhere too.
    final above = <String>{};
    for (final id in ids) {
      var parent = parents[id];
      while (parent != null && above.add(parent)) {
        parent = parents[parent];
      }
    }

    return [
      for (final t in allTags)
        if (!ids.contains(t.id))
          _shownUnder(t, parents[t.id], shownParent, above.contains(t.id)),
    ];
  }

  static Tag _shownUnder(
    Tag tag,
    String? parent,
    String? Function(String?) shownParent,
    bool holdsARemovedShelf,
  ) {
    final shown = shownParent(parent);
    if (shown == parent && !holdsARemovedShelf) return tag;
    return Tag(
      id: tag.id,
      name: tag.name,
      parentId: shown,
      path: tag.path,
      count: tag.count,
      totalCount: tag.totalCount,
      children: tag.children,
      coverPaths: tag.coverPaths,
      subtreeCount: holdsARemovedShelf ? null : tag.subtreeCount,
      subtreeTotalCount: holdsARemovedShelf ? null : tag.subtreeTotalCount,
    );
  }

  /// One tree index per list instance. Screens ask for the children and the
  /// total of every row they draw, so recomputing the index per call made a
  /// whole-tree screen quadratic. A list is only ever replaced on reload or
  /// grown in place (the length check catches that), and [Tag] is immutable.
  static final _treeIndexCache = Expando<_TreeIndex>('shelfTreeIndex');

  static _TreeIndex _treeIndexOf(List<Tag> allTags) {
    final cached = _treeIndexCache[allTags];
    if (cached != null && cached.length == allTags.length) return cached;
    final built = _TreeIndex.build(allTags);
    _treeIndexCache[allTags] = built;
    return built;
  }

  /// Stored parent per id, an empty parent read as none.
  static Map<String, String?> _parentIndex(List<Tag> allTags) => {
    for (final t in allTags)
      if (t.id.isNotEmpty)
        t.id: (t.parentId == null || t.parentId!.isEmpty) ? null : t.parentId,
  };

  static String? _effectiveParentIn(Tag tag, Map<String, String?> parentOf) {
    final parent = tag.parentId;
    if (parent == null || parent.isEmpty) return null;
    if (!parentOf.containsKey(parent)) return null;
    // Climb from the parent: meeting this tag again means it is in a cycle.
    final seen = <String>{};
    String? current = parent;
    while (current != null && seen.add(current)) {
      if (current == tag.id) return null;
      current = parentOf[current];
    }
    return parent;
  }

  /// Get all descendant IDs (children, grandchildren, etc.) for this tag.
  /// Requires a flat list of all tags; terminates on any tree sync can bring
  /// (see [effectiveParentId]).
  static Set<String> getDescendantIds(String tagId, List<Tag> allTags) {
    final children = _treeIndexOf(allTags).children;
    final descendants = <String>{};
    final pending = <String>[tagId];
    while (pending.isNotEmpty) {
      for (final child in children[pending.removeLast()] ?? const <Tag>[]) {
        if (child.id.isNotEmpty &&
            child.id != tagId &&
            descendants.add(child.id)) {
          pending.add(child.id);
        }
      }
    }
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

  /// The tag carrying [name] in [allTags], if any. Compared the way subjects
  /// are stored: bare names, trimmed, case-insensitively.
  static Tag? byName(List<Tag> allTags, String? name) {
    if (name == null) return null;
    final target = name.trim().toLowerCase();
    for (final tag in allTags) {
      if (tag.name.trim().toLowerCase() == target) return tag;
    }
    return null;
  }

  /// First-level tags: no parent, or one that reads as none (see
  /// [effectiveParentId]). In [compareShelves] order.
  static List<Tag> getRootTags(List<Tag> allTags) =>
      List.of(childrenIndex(allTags)[null] ?? const <Tag>[]);

  /// Direct children of a tag, as the tree shows them (see
  /// [effectiveParentId]). In [compareShelves] order.
  static List<Tag> getDirectChildren(String tagId, List<Tag> allTags) =>
      List.of(childrenIndex(allTags)[tagId] ?? const <Tag>[]);

  /// Every level of the tree in one pass: the tags under each effective
  /// parent id (null for the first level), each list in [compareShelves]
  /// order. A caller rendering a whole tree builds this once instead of
  /// asking [getDirectChildren] per node, which recomputes it every time.
  static Map<String?, List<Tag>> childrenIndex(List<Tag> allTags) =>
      _treeIndexOf(allTags).children;
}

/// The effective parents of a tag list and its children per level, computed
/// together and read-only, since one instance is shared by every caller of
/// the same list.
class _TreeIndex {
  final int length;
  final Map<String, String?> parents;
  final Map<String?, List<Tag>> children;

  _TreeIndex._(this.length, this.parents, this.children);

  factory _TreeIndex.build(List<Tag> allTags) {
    final stored = Tag._parentIndex(allTags);
    final parents = {
      for (final t in allTags) t.id: Tag._effectiveParentIn(t, stored),
    };
    final levels = <String?, List<Tag>>{};
    for (final tag in allTags) {
      levels.putIfAbsent(parents[tag.id], () => []).add(tag);
    }
    return _TreeIndex._(
      allTags.length,
      Map.unmodifiable(parents),
      Map.unmodifiable({
        for (final entry in levels.entries)
          entry.key: List<Tag>.unmodifiable(entry.value..sort(compareShelves)),
      }),
    );
  }
}

/// The one order shelves are listed in, everywhere in the app.
///
/// Alphabetical the way a reader expects it: case and accents ignored, so
/// "écrits" sits with the e's and "atelier" before "Bureau", and digits
/// compared as numbers, so "Tome 2" comes before "Tome 10". Dart has no
/// locale collation and the core ships without ICU, so accented Latin letters
/// are folded to their base letter here, without a new dependency. Names that
/// fold to the same text fall back to their raw order, so the sort is stable.
int compareShelfNames(String a, String b) {
  final folded = _compareNatural(_foldShelfName(a), _foldShelfName(b));
  return folded != 0 ? folded : a.compareTo(b);
}

/// [compareShelfNames] over tags, by name.
int compareShelves(Tag a, Tag b) => compareShelfNames(a.name, b.name);

/// [name] as [compareShelfNames] sees it: trimmed, lowercased, accented
/// Latin letters folded. Two names with the same key are the same shelf to
/// a reader, so a search or a "name taken" check compares these keys.
String shelfNameKey(String name) => _foldShelfName(name);

/// The shelf a reader would take [name] for: same name once case and accents
/// are folded. Only to say a typed name is taken: names stay unique byte for
/// byte in the core.
Tag? shelfTakenBy(List<Tag> tags, String name) {
  final key = shelfNameKey(name);
  for (final tag in tags) {
    if (shelfNameKey(tag.name) == key) return tag;
  }
  return null;
}

const _foldedLetters = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ș': 's',
  'ß': 'ss',
  'ť': 't',
  'ţ': 't',
  'ț': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};

String _foldShelfName(String name) {
  final lower = name.trim().toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_foldedLetters[char] ?? char);
  }
  return out.toString();
}

final _leadingZeros = RegExp(r'^0+(?=.)');

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// Compare with runs of digits read as numbers.
int _compareNatural(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final startA = i;
      final startB = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      // Compare digit runs by value without overflowing: strip leading
      // zeros, then the longer run is the larger number.
      final runA = a.substring(startA, i).replaceFirst(_leadingZeros, '');
      final runB = b.substring(startB, j).replaceFirst(_leadingZeros, '');
      if (runA.length != runB.length) return runA.length - runB.length;
      final byDigits = runA.compareTo(runB);
      if (byDigits != 0) return byDigits;
      continue;
    }
    if (ca != cb) return ca - cb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

/// The number a shelf badge must print under [scope].
///
/// A badge that disagrees with the list its tap opens is worse than no badge:
/// a shelf filled by importing a wishlist announced 0 and then showed ten
/// books, which is what sent this here. Rust reports both scopes and the
/// choice is made where the reader's remembered axis lives (ADR-063).
///
/// The "not owned" scope is the exact complement, floored at zero so a Tag
/// built without a total (it then defaults to [Tag.count]) reports nothing
/// rather than a negative.
int countForOwnershipScope(Tag tag, String scope) {
  switch (scope) {
    case OwnershipScope.all:
      return tag.totalCount;
    case OwnershipScope.notOwned:
      final hidden = tag.totalCount - tag.count;
      return hidden < 0 ? 0 : hidden;
    default:
      return tag.count;
  }
}

/// The books of [tag] and of its sub-shelves under the ownership [scope]: what
/// a card announces, each book once.
///
/// A tag from no listing, or above a shelf waiting on its Undo, has no such
/// count from the core and adds up its shelves over [shown], which counts twice
/// a book on a shelf and its sub-shelf.
int aggregatedCountForScope(Tag tag, List<Tag> shown, String scope) {
  final owned = tag.subtreeCount;
  final total = tag.subtreeTotalCount;
  if (owned != null && total != null) {
    return countForOwnershipScope(
      Tag(id: tag.id, name: tag.name, count: owned, totalCount: total),
      scope,
    );
  }
  final descendants = Tag.getDescendantIds(tag.id, shown);
  var sum = countForOwnershipScope(tag, scope);
  for (final t in shown) {
    if (descendants.contains(t.id)) sum += countForOwnershipScope(t, scope);
  }
  return sum;
}
