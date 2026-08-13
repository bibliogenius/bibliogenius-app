import 'package:bibliogenius/utils/book_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookDisplay.resolveTitle', () {
    const untitled = 'Untitled book';

    test('keeps the title when the book has one', () {
      expect(
        BookDisplay.resolveTitle(
          title: 'Le Mythe de Sisyphe',
          isbn: '9782070322886',
          untitledLabel: () => untitled,
        ),
        'Le Mythe de Sisyphe',
      );
    });

    test('falls back to the ISBN for a title-less book', () {
      // The peer-screen defect: a manually entered book pushed to the hub
      // with title "" used to render as a blank tile.
      expect(
        BookDisplay.resolveTitle(
          title: '',
          isbn: '9782070322886',
          untitledLabel: () => untitled,
        ),
        '9782070322886',
      );
    });

    test('falls back to the placeholder when the ISBN is missing too', () {
      expect(
        BookDisplay.resolveTitle(
          title: '',
          isbn: null,
          untitledLabel: () => untitled,
        ),
        untitled,
      );
      expect(
        BookDisplay.resolveTitle(
          title: '',
          isbn: '',
          untitledLabel: () => untitled,
        ),
        untitled,
      );
    });

    test('treats a whitespace-only title or ISBN as missing', () {
      expect(
        BookDisplay.resolveTitle(
          title: '   ',
          isbn: '9782070322886',
          untitledLabel: () => untitled,
        ),
        '9782070322886',
      );
      expect(
        BookDisplay.resolveTitle(
          title: '',
          isbn: '  ',
          untitledLabel: () => untitled,
        ),
        untitled,
      );
    });
  });

  group('BookDisplay.resolveCoverLabel', () {
    test('appends the author when known', () {
      expect(
        BookDisplay.resolveCoverLabel(title: 'Nadja', author: 'André Breton'),
        'Nadja, André Breton',
      );
    });

    test('announces the title alone when the author is missing or blank', () {
      expect(
        BookDisplay.resolveCoverLabel(title: 'Nadja', author: null),
        'Nadja',
      );
      expect(
        BookDisplay.resolveCoverLabel(title: 'Nadja', author: ' '),
        'Nadja',
      );
    });

    test('a title-less book still announces its fallback identity', () {
      // Rule A1: the screen reader must never land on an empty label.
      final title = BookDisplay.resolveTitle(
        title: '',
        isbn: '9782070322886',
        untitledLabel: () => 'Untitled book',
      );
      expect(
        BookDisplay.resolveCoverLabel(title: title, author: null),
        '9782070322886',
      );
    });
  });
}
