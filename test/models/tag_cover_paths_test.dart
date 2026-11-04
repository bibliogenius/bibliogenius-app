import 'package:bibliogenius/models/tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shelf's thumbnail covers travel with every copy the app makes of it.
void main() {
  const covers = ['https://c/a.jpg', '/covers/b.jpg'];

  test('defaults to no cover, so hand-built tags need not say', () {
    expect(Tag(id: 's1', name: 'Novels', count: 0).coverPaths, isEmpty);
  });

  test('the HTTP listing names them cover_urls', () {
    final tag = Tag.fromJson({
      'name': 'Novels',
      'count': 2,
      'cover_urls': covers,
    });
    expect(tag.coverPaths, covers);
  });

  test('a tag written out carries no cover path off the device', () {
    final json = Tag(
      id: 's1',
      name: 'Novels',
      count: 1,
      coverPaths: covers,
    ).toJson();
    expect(json.keys, isNot(contains('cover_paths')));
    expect(json.keys, isNot(contains('cover_urls')));
  });

  test('a sub-shelf shown under its grandparent keeps its covers', () {
    final tags = [
      Tag(id: 'p', name: 'Living room', count: 0),
      Tag(id: 'm', name: 'Novels', parentId: 'p', count: 0),
      Tag(id: 'c', name: 'Crime', parentId: 'm', count: 1, coverPaths: covers),
    ];

    final shown = Tag.withoutShelves(tags, {'m'});

    final crime = shown.singleWhere((t) => t.id == 'c');
    expect(crime.parentId, 'p');
    expect(crime.coverPaths, covers);
  });

  test('a copy with new children keeps its covers', () {
    final tag = Tag(
      id: 's1',
      name: 'Novels',
      count: 1,
      totalCount: 4,
      coverPaths: covers,
    );
    expect(tag.copyWithChildren(const []).coverPaths, covers);
    expect(tag.copyWithChildren(const []).totalCount, 4);
  });
}
