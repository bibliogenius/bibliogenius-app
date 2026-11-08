import 'package:bibliogenius/utils/shelf_spelling.dart';
import 'package:flutter_test/flutter_test.dart';

// The same cases as the core's `shelf_spelling` tests: both sides must agree.
void main() {
  test('a name differing by case alone stands for its shelf', () {
    final spelling = ShelfSpelling(['Polar', 'Étrangers']);
    expect(spelling.shelfOf('polar'), 'Polar');
    expect(spelling.shelfOf(' POLAR '), 'Polar');
    expect(spelling.shelfOf('étrangers'), 'Étrangers');
  });

  test('accents stay apart and an unknown name stands for itself', () {
    final spelling = ShelfSpelling(['Étagère']);
    expect(spelling.shelfOf('etagere'), 'etagere');
    expect(spelling.shelfOf('Roman'), 'Roman');
  });

  test(
    'an exact shelf keeps its name and the first shelf takes the others',
    () {
      final spelling = ShelfSpelling(['Polar', 'POLAR']);
      expect(spelling.shelfOf('Polar'), 'Polar');
      expect(spelling.shelfOf('POLAR'), 'POLAR');
      // "POLAR" sorts before "Polar".
      expect(spelling.shelfOf('polar'), 'POLAR');
    },
  );
}
