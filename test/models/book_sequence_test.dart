import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/book_sequence.dart';

Book _book(String? id) => Book(id: id, title: 'Book $id');

void main() {
  group('BookSequence.around', () {
    test('places the opened book among its neighbours', () {
      final books = [_book('a'), _book('b'), _book('c')];
      final sequence = BookSequence.around(books, books[1])!;

      expect(sequence.current.id, 'b');
      expect(sequence.previous?.id, 'a');
      expect(sequence.next?.id, 'c');
    });

    test('has no previous on the first book and no next on the last', () {
      final books = [_book('a'), _book('b')];

      final first = BookSequence.around(books, books.first)!;
      expect(first.previous, isNull);
      expect(first.next?.id, 'b');

      final last = BookSequence.around(books, books.last)!;
      expect(last.previous?.id, 'a');
      expect(last.next, isNull);
    });

    test('is null when there is nothing to step to', () {
      final alone = _book('a');
      expect(BookSequence.around([alone], alone), isNull);
      expect(BookSequence.around([], alone), isNull);
    });

    test('is null when the opened book is not in the list', () {
      expect(BookSequence.around([_book('a'), _book('b')], _book('z')), isNull);
    });

    test('skips books without an id: their page cannot be opened', () {
      final books = [_book('a'), _book(null), _book('c')];
      final sequence = BookSequence.around(books, books.first)!;

      expect(sequence.next?.id, 'c');
    });

    test('keeps the first occurrence of a book listed twice', () {
      final books = [_book('a'), _book('b'), _book('a'), _book('c')];
      final sequence = BookSequence.around(books, books[1])!;

      expect(sequence.next?.id, 'c');
      expect(sequence.previous?.id, 'a');
    });

    test('does not follow later changes to the source list', () {
      final books = [_book('a'), _book('b')];
      final sequence = BookSequence.around(books, books.first)!;
      books.add(_book('c'));

      final last = sequence.step(1);
      expect(last.next, isNull);
    });
  });

  group('BookSequence.routeExtra', () {
    test('hands the route a sequence when there is a neighbour', () {
      final books = [_book('a'), _book('b')];
      expect(BookSequence.routeExtra(books, books.first), isA<BookSequence>());
    });

    test('hands the route the book alone otherwise', () {
      final alone = _book('a');
      expect(BookSequence.routeExtra([alone], alone), same(alone));
    });
  });

  group('BookSequence.step', () {
    test('moves to the neighbour', () {
      final books = [_book('a'), _book('b'), _book('c')];
      final sequence = BookSequence.around(books, books.first)!;

      expect(sequence.step(1).current.id, 'b');
      expect(sequence.step(1).step(1).current.id, 'c');
      expect(sequence.step(1).step(-1).current.id, 'a');
    });
  });
}
