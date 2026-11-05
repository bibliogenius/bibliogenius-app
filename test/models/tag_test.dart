import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/utils/book_filters.dart';

Tag _shelf(String id, {String? parent}) =>
    Tag(id: id, name: id, parentId: parent, count: 0);

List<String> _ids(Iterable<Tag> tags) => tags.map((t) => t.id).toList()..sort();

void main() {
  group('tree helpers tolerate what sync can bring', () {
    test('a plain tree is read as stored', () {
      final tags = [
        _shelf('top'),
        _shelf('middle', parent: 'top'),
        _shelf('leaf', parent: 'middle'),
      ];

      expect(_ids(Tag.getRootTags(tags)), ['top']);
      expect(_ids(Tag.getDirectChildren('top', tags)), ['middle']);
      expect(Tag.getDescendantIds('top', tags), {'middle', 'leaf'});
    });

    test('a cycle A -> B -> A puts both shelves at the first level', () {
      final tags = [_shelf('a', parent: 'b'), _shelf('b', parent: 'a')];

      expect(_ids(Tag.getRootTags(tags)), ['a', 'b']);
      expect(Tag.getDirectChildren('a', tags), isEmpty);
      expect(Tag.getDirectChildren('b', tags), isEmpty);
      // Terminates instead of recursing forever.
      expect(Tag.getDescendantIds('a', tags), isEmpty);
    });

    test('a shelf that is its own parent sits at the first level', () {
      final tags = [_shelf('a', parent: 'a')];

      expect(_ids(Tag.getRootTags(tags)), ['a']);
      expect(Tag.getDescendantIds('a', tags), isEmpty);
    });

    test('a shelf below a cycle stays under its own parent', () {
      final tags = [
        _shelf('a', parent: 'b'),
        _shelf('b', parent: 'a'),
        _shelf('below', parent: 'a'),
      ];

      expect(_ids(Tag.getRootTags(tags)), ['a', 'b']);
      expect(_ids(Tag.getDirectChildren('a', tags)), ['below']);
      expect(Tag.getDescendantIds('a', tags), {'below'});
    });

    test('the book list filter expands a shelf over a cycle and terminates', () {
      // The filter behind `/shelves?tag=` widens a shelf to its subtree.
      final tags = [
        Tag(id: 'a', name: 'A', parentId: 'b', count: 0),
        Tag(id: 'b', name: 'B', parentId: 'a', count: 0),
        Tag(id: 'below', name: 'Below', parentId: 'a', count: 0),
        Tag(id: 'orphan', name: 'Orphan', parentId: 'gone', count: 0),
      ];

      expect(Tag.getTagNamesWithDescendants(tags[0], tags), {'a', 'below'});
      expect(Tag.getTagNamesWithDescendants(tags[1], tags), {'b'});
      expect(Tag.getTagNamesWithDescendants(tags[3], tags), {'orphan'});
      expect(Tag.getAggregatedCount(tags[0], tags), 0);
    });

    test('a shelf whose parent no longer exists sits at the first level', () {
      final tags = [_shelf('top'), _shelf('orphan', parent: 'deleted')];

      expect(_ids(Tag.getRootTags(tags)), ['orphan', 'top']);
      expect(Tag.effectiveParentId(tags[1], tags), isNull);
    });
  });

  test('the tree helpers list shelves in compareShelfNames order', () {
    final tags = [
      Tag(id: 'z', name: 'Zola', count: 0),
      Tag(id: 'e', name: 'écrits', count: 0),
      Tag(id: 'b', name: 'Bureau', count: 0),
      Tag(id: 'c2', name: 'Tome 10', parentId: 'b', count: 0),
      Tag(id: 'c1', name: 'Tome 2', parentId: 'b', count: 0),
    ];

    expect(Tag.getRootTags(tags).map((t) => t.name), [
      'Bureau',
      'écrits',
      'Zola',
    ]);
    expect(Tag.getDirectChildren('b', tags).map((t) => t.name), [
      'Tome 2',
      'Tome 10',
    ]);
  });

  test('childrenIndex agrees with the per-node helpers on any shape', () {
    final tags = [
      Tag(id: 'top', name: 'Top', count: 0),
      Tag(id: 'b2', name: 'Tome 10', parentId: 'top', count: 0),
      Tag(id: 'b1', name: 'Tome 2', parentId: 'top', count: 0),
      Tag(id: 'x', name: 'X', parentId: 'y', count: 0),
      Tag(id: 'y', name: 'Y', parentId: 'x', count: 0),
      Tag(id: 'o', name: 'Orphan', parentId: 'gone', count: 0),
    ];

    final index = Tag.childrenIndex(tags);

    expect(
      index[null]!.map((t) => t.id),
      Tag.getRootTags(tags).map((t) => t.id),
    );
    expect(index[null]!.map((t) => t.name), ['Orphan', 'Top', 'X', 'Y']);
    expect(index['top']!.map((t) => t.name), ['Tome 2', 'Tome 10']);
    expect(index.containsKey('x'), isFalse, reason: 'cycle members own none');
  });

  group('the tree index is computed once per list', () {
    test('a list that grows in place is read again', () {
      final tags = [Tag(id: 'a', name: 'A', count: 0)];
      expect(Tag.getRootTags(tags).map((t) => t.id), ['a']);

      tags.add(Tag(id: 'b', name: 'B', parentId: 'a', count: 0));

      expect(Tag.getDirectChildren('a', tags).map((t) => t.id), ['b']);
      expect(Tag.getDescendantIds('a', tags), {'b'});
    });

    test('a caller cannot corrupt what the next caller reads', () {
      final tags = [
        Tag(id: 'a', name: 'A', count: 0),
        Tag(id: 'b', name: 'B', parentId: 'a', count: 0),
      ];

      Tag.getRootTags(tags).clear();
      Tag.getDirectChildren('a', tags).clear();

      expect(Tag.getRootTags(tags).map((t) => t.id), ['a']);
      expect(Tag.getDirectChildren('a', tags).map((t) => t.id), ['b']);
      expect(
        () => Tag.childrenIndex(tags)[null]!.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('compareShelfNames', () {
    test('ignores case and accents', () {
      final names = ['Zola', 'écrits', 'Bureau', 'Étagère', 'atelier']
        ..sort(compareShelfNames);

      expect(names, ['atelier', 'Bureau', 'écrits', 'Étagère', 'Zola']);
    });

    test('orders numbers naturally', () {
      final names = ['Tome 10', 'Tome 2', 'Tome 1']..sort(compareShelfNames);

      expect(names, ['Tome 1', 'Tome 2', 'Tome 10']);
    });

    test('folds the accented Latin letters of the shipped languages', () {
      // de, tr, pt-BR, es, it, fr letters land next to their base letter.
      final names = ['Zebra', 'Öl', 'Ostern', 'Şehir', 'Sahne', 'Ação', 'Abc']
        ..sort(compareShelfNames);

      expect(names, ['Abc', 'Ação', 'Öl', 'Ostern', 'Sahne', 'Şehir', 'Zebra']);
    });

    test('is total: names equal once folded still get a stable order', () {
      expect(compareShelfNames('Etagere', 'Étagère'), isNot(0));
      expect(
        compareShelfNames('Etagere', 'Étagère'),
        -compareShelfNames('Étagère', 'Etagere'),
      );
    });
  });

  group('aggregatedCountForScope', () {
    final parent = Tag(
      id: 'p',
      name: 'Parent',
      count: 1,
      totalCount: 2,
      subtreeCount: 3,
      subtreeTotalCount: 7,
    );
    final child = Tag(
      id: 'c',
      name: 'Child',
      parentId: 'p',
      count: 3,
      totalCount: 6,
      subtreeCount: 3,
      subtreeTotalCount: 6,
    );

    test('reads the core\'s subtree counts, which hold each book once', () {
      final shown = [parent, child];
      expect(aggregatedCountForScope(parent, shown, OwnershipScope.library), 3);
      expect(aggregatedCountForScope(parent, shown, OwnershipScope.all), 7);
      expect(
        aggregatedCountForScope(parent, shown, OwnershipScope.notOwned),
        4,
      );
    });

    test('a tag from no listing adds up its shelves, as before', () {
      final a = Tag(id: 'a', name: 'A', count: 1);
      final b = Tag(id: 'b', name: 'B', parentId: 'a', count: 2);
      expect(aggregatedCountForScope(a, [a, b], OwnershipScope.library), 3);
    });

    test('a tag shown under another parent keeps its subtree counts', () {
      final shown = Tag.withoutShelves([parent, child], {'p'});
      expect(shown.single.subtreeCount, 3);
      expect(shown.single.subtreeTotalCount, 6);
    });
  });
}
