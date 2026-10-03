import 'dart:convert';

import 'package:bibliogenius/utils/import_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('givenNameFirst turns a Babelio author around', () {
    test('surname then given name', () {
      expect(givenNameFirst('Zask Joëlle'), 'Joëlle Zask');
      expect(givenNameFirst('Schmitt Éric-Emmanuel'), 'Éric-Emmanuel Schmitt');
    });

    test('several given names stay together after the surname', () {
      expect(givenNameFirst('Oates Joyce Carol'), 'Joyce Carol Oates');
      expect(givenNameFirst('Tapply William G.'), 'William G. Tapply');
      expect(givenNameFirst('Ólafsdóttir Auður Ava'), 'Auður Ava Ólafsdóttir');
    });

    test('a particle at the head of the surname keeps the next word', () {
      expect(givenNameFirst('Le Carré John'), 'John Le Carré');
      expect(givenNameFirst('Da Costa Mélissa'), 'Mélissa Da Costa');
      expect(givenNameFirst('Van der Meer Jan'), 'Jan Van der Meer');
    });

    test('a particle pushed to the end goes back before the surname', () {
      expect(givenNameFirst('Bruycker Daniel de'), 'Daniel de Bruycker');
      expect(givenNameFirst('La Fontaine Jean de'), 'Jean de La Fontaine');
    });

    test('a single name, with the trailing space Babelio leaves', () {
      expect(givenNameFirst('Molière '), 'Molière');
      expect(givenNameFirst('Xinran'), 'Xinran');
    });

    test('a comma says where the surname ends', () {
      expect(givenNameFirst('Vargas Llosa, Mario'), 'Mario Vargas Llosa');
    });

    test('co-authors are each turned around', () {
      expect(
        givenNameFirst('Goscinny René & Uderzo Albert'),
        'René Goscinny, Albert Uderzo',
      );
    });
  });

  group('parseReadingStatus', () {
    test('Babelio statuses', () {
      expect(parseReadingStatus('Lu'), 'read');
      expect(parseReadingStatus('A lire'), 'to_read');
      expect(parseReadingStatus('À lire'), 'to_read');
      expect(parseReadingStatus('En cours'), 'reading');
      expect(parseReadingStatus('Pense-bête'), 'wanting');
      expect(parseReadingStatus('Abandonné'), 'abandoned');
    });

    test('Goodreads shelves', () {
      expect(parseReadingStatus('read'), 'read');
      expect(parseReadingStatus('currently-reading'), 'reading');
      expect(parseReadingStatus('to-read'), 'to_read');
    });

    test('an unknown or empty value is no status, not a guess', () {
      expect(parseReadingStatus('favoris'), isNull);
      expect(parseReadingStatus(''), isNull);
      expect(parseReadingStatus(null), isNull);
    });
  });

  group('parseImportedRating stores out of 10', () {
    test('a 5-star rating doubles, half stars included', () {
      expect(parseImportedRating('4', scale: 5), 8);
      expect(parseImportedRating('3.5', scale: 5), 7);
      expect(parseImportedRating('4,5', scale: 5), 9);
    });

    test('0 is "not rated" in Babelio and Goodreads', () {
      expect(parseImportedRating('0.0', scale: 5), isNull);
      expect(parseImportedRating('0', scale: 5), isNull);
    });

    test('a cell that states its scale wins over the column', () {
      expect(parseImportedRating('7/10', scale: 5), 7);
      expect(parseImportedRating('4/5', scale: 10), 8);
    });

    test('out of range or not a number is no rating', () {
      expect(parseImportedRating('6', scale: 5), isNull);
      expect(parseImportedRating('★★★', scale: 5), isNull);
      expect(parseImportedRating(null, scale: 5), isNull);
    });

    test('the scale is inferred from the column when unknown', () {
      expect(inferRatingScale(['3', '5', null, '']), 5);
      expect(inferRatingScale(['3', '8']), 10);
    });
  });

  group('parseImportedDate', () {
    test('ISO, Goodreads and day-first dates', () {
      expect(parseImportedDate('2024-06-09'), '2024-06-09T00:00:00.000');
      expect(parseImportedDate('2024/06/09'), '2024-06-09T00:00:00.000');
      expect(
        parseImportedDate('2026-09-05 13:42:22'),
        '2026-09-05T00:00:00.000',
      );
      expect(parseImportedDate('09/06/2024'), '2024-06-09T00:00:00.000');
    });

    test('Babelio\'s empty date and impossible dates are no date', () {
      expect(parseImportedDate('0000-00-00'), isNull);
      expect(parseImportedDate('2024-02-31'), isNull);
      expect(parseImportedDate('2024-13-01'), isNull);
      expect(parseImportedDate('bientôt'), isNull);
    });
  });

  group('ImportSource.detect', () {
    test('Babelio, by its entry-date column', () {
      final source = ImportSource.detect([
        'isbn',
        'titre',
        'auteur',
        'editeur',
        'date de publication',
        'date d`entrée dans babelio',
        'statut',
        'note',
      ]);
      expect(source, ImportSource.babelio);
      expect(source.author('Zask Joëlle'), 'Joëlle Zask');
    });

    test('Goodreads, by its exclusive shelf and rating', () {
      expect(
        ImportSource.detect([
          'title',
          'author',
          'my rating',
          'exclusive shelf',
        ]),
        ImportSource.goodreads,
      );
    });

    test('anything else keeps its authors as written', () {
      final source = ImportSource.detect(['titre', 'auteur']);
      expect(source, ImportSource.generic);
      expect(source.author('Joëlle Zask'), 'Joëlle Zask');
    });
  });

  group('ReadingColumns', () {
    test('Babelio ignores its entry date: it is not a reading date', () {
      final columns = ReadingColumns.resolve([
        'titre',
        'date d`entrée dans babelio',
        'statut',
        'note',
      ]);
      final cells = ['Martin Eden', '2024-06-09 19:07:24', 'Lu', '4.5'];
      final read = columns.read((i) => i >= 0 ? cells[i] : null);
      expect(read.status, 'read');
      expect(read.rating, 9);
      expect(read.finishedAt, isNull);
      expect(read.startedAt, isNull);
    });

    test('a finish date makes a book on the "to read" shelf read', () {
      final columns = ReadingColumns.resolve([
        'title',
        'exclusive shelf',
        'date read',
      ]);
      final cells = ['Martin Eden', 'to-read', '2024/06/09'];
      final read = columns.read((i) => i >= 0 ? cells[i] : null);
      expect(read.status, 'read');
      expect(read.finishedAt, '2024-06-09T00:00:00.000');
    });

    test('a file with no reading column says so', () {
      expect(ReadingColumns.resolve(['titre', 'auteur', 'isbn']).any, isFalse);
    });
  });

  group('decodeImportText', () {
    test('UTF-8, with or without its byte order mark', () {
      expect(decodeImportText(utf8.encode('Œuvre’s')), 'Œuvre’s');
      expect(
        decodeImportText([0xEF, 0xBB, 0xBF, ...utf8.encode('Zask')]),
        'Zask',
      );
    });

    test('Windows-1252, as Babelio writes it', () {
      // "Joëlle", "cœur", "l’été" in Windows-1252.
      expect(decodeImportText([0x4A, 0x6F, 0xEB, 0x6C, 0x6C, 0x65]), 'Joëlle');
      expect(decodeImportText([0x63, 0x9C, 0x75, 0x72]), 'cœur');
      expect(decodeImportText([0x6C, 0x92, 0xE9, 0x74, 0xE9]), 'l’été');
    });
  });
}
