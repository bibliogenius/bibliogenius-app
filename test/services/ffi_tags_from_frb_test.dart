import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

/// The shelves tab reads its badges and thumbnails through this conversion:
/// a field it drops is a number or a cover the tab never shows.
void main() {
  test('every field of a shelf reaches the app model', () {
    final tags = tagsFromFrb([
      const frb.FrbTag(
        id: 's2',
        name: 'Novels',
        parentId: 's1',
        count: 2,
        totalCount: 5,
        coverPaths: ['/covers/a.jpg', 'https://c/b.jpg'],
        subtreeCount: 3,
        subtreeTotalCount: 7,
      ),
    ]);

    final tag = tags.single;
    expect(tag.id, 's2');
    expect(tag.name, 'Novels');
    expect(tag.parentId, 's1');
    expect(tag.count, 2);
    expect(tag.totalCount, 5);
    expect(tag.coverPaths, ['/covers/a.jpg', 'https://c/b.jpg']);
    expect(tag.subtreeCount, 3);
    expect(tag.subtreeTotalCount, 7);
  });

  test('no shelf gives no tag', () {
    expect(tagsFromFrb(const []), isEmpty);
  });
}
