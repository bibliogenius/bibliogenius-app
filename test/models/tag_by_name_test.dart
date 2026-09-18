import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/tag.dart';

/// `Tag.byName` is how a shelf reached by its name (the shelves grid links to
/// `/shelves?tag=Genre`) becomes a tag the book list can expand to its
/// sub-shelves. On the bare string a parent whose books all sit in its
/// sub-shelves opened as an empty list.
void main() {
  final genre = Tag(id: 'g', name: 'Genre', count: 0);
  final roman = Tag(id: 'r', name: 'Roman', parentId: 'g', count: 3);
  final tags = [genre, roman];

  test('resolves a shelf by name the way subjects spell it', () {
    expect(Tag.byName(tags, 'Genre'), same(genre));
    expect(Tag.byName(tags, ' genre '), same(genre), reason: 'trimmed, any case');
  });

  test('an unknown or absent name resolves to nothing', () {
    expect(Tag.byName(tags, 'Polar'), isNull);
    expect(Tag.byName(tags, null), isNull);
  });

  test('the resolved parent expands to its whole subtree', () {
    final shelf = Tag.byName(tags, 'Genre')!;
    final names = Tag.getTagNamesWithDescendants(shelf, tags);
    expect(names, containsAll(['genre', 'roman']));
  });
}
