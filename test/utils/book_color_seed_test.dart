import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/book_color_seed.dart';

void main() {
  group('bookColorSeed', () {
    test('uses local id when available and non-zero', () {
      final b = Book(id: 42, title: 'T');
      expect(bookColorSeed(b), 42);
    });

    test('falls back to ISBN hash when id is null', () {
      final b = Book(id: null, isbn: '9781234567890', title: 'T');
      expect(bookColorSeed(b), '9781234567890'.hashCode);
    });

    test('falls back to ISBN hash when id is 0 (peer library pattern)', () {
      final b = Book(id: 0, isbn: '9781234567890', title: 'T');
      expect(bookColorSeed(b), '9781234567890'.hashCode);
    });

    test('falls back to title|author hash when id and isbn are missing', () {
      final a = Book(title: 'Les damnés de la terre', author: 'Frantz Fanon');
      final b = Book(title: 'Quatre soeurs', author: 'Laura Alcoba');
      expect(bookColorSeed(a), isNot(bookColorSeed(b)));
      expect(bookColorSeed(a), isNot(0));
      expect(bookColorSeed(b), isNot(0));
    });

    test('produces distinct seeds for a peer library (id null, isbn null)', () {
      final titles = [
        'Les irresponsables',
        '1945, le retour des absents',
        'Quatre soeurs',
        'Albert Camus',
        'Journaliste, psy et prêtre',
        'Correspondance 1944-1959',
      ];
      final seeds = titles.map((t) => bookColorSeed(Book(title: t))).toSet();
      expect(seeds.length, titles.length,
          reason: 'Every title must yield a distinct seed');
    });

    test('never returns 0 (protects against hue=0 collapse)', () {
      final b = Book(title: '', author: '');
      expect(bookColorSeed(b), isNot(0));
    });
  });
}
