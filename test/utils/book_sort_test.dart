import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/book_sort.dart';

Book _book(String title, {String? author}) =>
    Book(title: title, author: author);

void main() {
  group('compareBooks - sort by author, ascending', () {
    test('sorts by author surname (last word), case-insensitive', () {
      final camus = _book('La Peste', author: 'Albert Camus');
      final zola = _book('Germinal', author: 'Emile Zola');
      expect(
        compareBooks(camus, zola, SortBy.author, SortDir.asc),
        lessThan(0),
      );
      expect(
        compareBooks(zola, camus, SortBy.author, SortDir.asc),
        greaterThan(0),
      );
    });

    test('falls back to title (ascending) when same author', () {
      final first = _book('L\'Etranger', author: 'Albert Camus');
      final second = _book('La Peste', author: 'Albert Camus');
      expect(
        compareBooks(first, second, SortBy.author, SortDir.asc),
        lessThan(0),
      );
      expect(
        compareBooks(second, first, SortBy.author, SortDir.asc),
        greaterThan(0),
      );
    });

    test('empty author goes to the bottom', () {
      final withAuthor = _book('La Peste', author: 'Albert Camus');
      final noAuthor = _book('Orphan');
      expect(
        compareBooks(noAuthor, withAuthor, SortBy.author, SortDir.asc),
        greaterThan(0),
        reason: 'empty author must compare greater than any non-empty',
      );
      expect(
        compareBooks(withAuthor, noAuthor, SortBy.author, SortDir.asc),
        lessThan(0),
      );
    });

    test('whitespace-only author is treated as empty', () {
      final blank = _book('Blank', author: '   ');
      final real = _book('Real', author: 'Hugo');
      expect(
        compareBooks(blank, real, SortBy.author, SortDir.asc),
        greaterThan(0),
      );
    });

    test('two empty-author books are sorted by title ascending', () {
      final a = _book('Apple');
      final b = _book('Banana');
      expect(compareBooks(a, b, SortBy.author, SortDir.asc), lessThan(0));
      expect(compareBooks(b, a, SortBy.author, SortDir.asc), greaterThan(0));
    });
  });

  group('compareBooks - sort by author, descending', () {
    test('reverses primary author order', () {
      final camus = _book('La Peste', author: 'Albert Camus');
      final zola = _book('Germinal', author: 'Emile Zola');
      expect(
        compareBooks(camus, zola, SortBy.author, SortDir.desc),
        greaterThan(0),
      );
      expect(
        compareBooks(zola, camus, SortBy.author, SortDir.desc),
        lessThan(0),
      );
    });

    test('empty author still goes to the bottom in descending', () {
      final withAuthor = _book('La Peste', author: 'Albert Camus');
      final noAuthor = _book('Orphan');
      expect(
        compareBooks(noAuthor, withAuthor, SortBy.author, SortDir.desc),
        greaterThan(0),
        reason: 'empty author must stay at the bottom in both directions',
      );
      expect(
        compareBooks(withAuthor, noAuthor, SortBy.author, SortDir.desc),
        lessThan(0),
      );
    });

    test('secondary title stays ascending even when primary is descending', () {
      // Two books by Zola - in Z-A mode, titles within Zola must still be A-Z.
      final germinal = _book('Germinal', author: 'Emile Zola');
      final nana = _book('Nana', author: 'Emile Zola');
      expect(
        compareBooks(germinal, nana, SortBy.author, SortDir.desc),
        lessThan(0),
      );
      expect(
        compareBooks(nana, germinal, SortBy.author, SortDir.desc),
        greaterThan(0),
      );
    });
  });

  group('compareBooks - sort by title', () {
    test('sorts by title ascending, case-insensitive', () {
      final a = _book('apple pie', author: 'X');
      final b = _book('Banana Bread', author: 'X');
      expect(compareBooks(a, b, SortBy.title, SortDir.asc), lessThan(0));
      expect(compareBooks(b, a, SortBy.title, SortDir.asc), greaterThan(0));
    });

    test('reverses order in descending', () {
      final a = _book('Apple', author: 'X');
      final b = _book('Banana', author: 'X');
      expect(compareBooks(a, b, SortBy.title, SortDir.desc), greaterThan(0));
    });

    test('falls back to author (ascending) when titles match', () {
      final camus = _book('Essays', author: 'Albert Camus');
      final zola = _book('Essays', author: 'Emile Zola');
      expect(compareBooks(camus, zola, SortBy.title, SortDir.asc), lessThan(0));
      expect(
        compareBooks(zola, camus, SortBy.title, SortDir.asc),
        greaterThan(0),
      );
    });

    test('empty-author secondary does not bubble: title is primary', () {
      // When primary key (title) differs, empty-author order follows title.
      final empty = _book('Apple');
      final withAuthor = _book('Banana', author: 'Zola');
      expect(
        compareBooks(empty, withAuthor, SortBy.title, SortDir.asc),
        lessThan(0),
      );
    });
  });

  group('sortBooks extension', () {
    test('applies compareBooks to a list in-place', () {
      final books = <Book>[
        _book('Orphan'),
        _book('La Peste', author: 'Albert Camus'),
        _book('Germinal', author: 'Emile Zola'),
      ];
      books.sortWith(SortBy.author, SortDir.asc);
      expect(books.map((b) => b.title).toList(), [
        'La Peste',
        'Germinal',
        'Orphan',
      ]);
    });

    test('empty authors bubble to the bottom in Z-A too', () {
      final books = <Book>[
        _book('Orphan'),
        _book('La Peste', author: 'Albert Camus'),
        _book('Germinal', author: 'Emile Zola'),
      ];
      books.sortWith(SortBy.author, SortDir.desc);
      expect(books.map((b) => b.title).toList(), [
        'Germinal',
        'La Peste',
        'Orphan',
      ]);
    });
  });
}
