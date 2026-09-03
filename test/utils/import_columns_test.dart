import 'package:bibliogenius/utils/import_columns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findAuthorColumn', () {
    test('a Gleeph export names no author at all', () {
      // Header row copied verbatim from _ressources/gleeph/ExportGleephClean.xlsx.
      // Gleeph exports the title and the ISBN and nothing about the author, so
      // no column lookup can rescue a Gleeph migration: the author has to come
      // from an ISBN lookup, which the import does not perform.
      final headers = [
        'book_title',
        'isbn',
        'creation_date_link',
        'wish',
        'own',
        'reading',
        'read',
        'favorite',
        'shelves',
      ];
      expect(findAuthorColumn(headers), -1);
    });

    test('finds a book_author column in a generic XLSX', () {
      final headers = ['book_title', 'book_author', 'isbn', 'shelves'];
      expect(findAuthorColumn(headers), 1);
    });

    test('finds the Goodreads author column, not the sorted variant', () {
      final headers = [
        'book id',
        'title',
        'author',
        'author l-f',
        'additional authors',
        'isbn',
      ];
      expect(findAuthorColumn(headers), 2);
    });

    test('prefers an exact name over an earlier partial match', () {
      // "additional authors" contains "author" but is not the author column.
      final headers = ['title', 'additional authors', 'author'];
      expect(findAuthorColumn(headers), 2);
    });

    test('an Inventaire export picks the labels, not the entity URLs', () {
      // "Authors URLs" comes first in the Inventaire header and contains
      // "author", so a plain partial match filed a wikidata URL as the author.
      final headers = [
        'edition title',
        'authors urls',
        'authors labels',
        'publisher label',
      ];
      expect(findAuthorColumn(headers), 2);
    });

    test('falls back to a partial match when no exact name is present', () {
      final headers = ['titre', 'nom auteur', 'isbn'];
      expect(findAuthorColumn(headers), 1);
    });

    test('finds the French column', () {
      expect(findAuthorColumn(['titre', 'auteur', 'ean']), 1);
    });

    test('returns -1 when the file names no author', () {
      expect(findAuthorColumn(['book_title', 'isbn', 'shelves']), -1);
    });

    test('ignores case and surrounding spaces', () {
      expect(findAuthorColumn(['Title', '  Author  ']), 1);
    });
  });

  group('findIsbnColumn', () {
    test('prefers the Goodreads ISBN13 column over ISBN', () {
      expect(findIsbnColumn(['Title', 'Author', 'ISBN', 'ISBN13']), 3);
    });

    test('takes any header mentioning isbn', () {
      expect(findIsbnColumn(['Edition title', 'Edition ISBN-13']), 1);
    });

    test('a French export names the barcode: ean', () {
      // Header of _ressources/import-repro/repro-ean-virgules.csv, the file
      // that reproduced a 2861-book library arriving without a single ISBN.
      expect(findIsbnColumn(['Titre', 'Auteur', 'EAN', 'Editeur', 'Annee']), 2);
      expect(findIsbnColumn(['titre', 'ean13']), 1);
    });

    test('isbn wins over ean when both are present', () {
      expect(findIsbnColumn(['ean', 'isbn']), 1);
    });

    test('returns -1 when the file names none', () {
      expect(findIsbnColumn(['Titre', 'Auteur', 'Editeur']), -1);
    });
  });

  group('detectCsvDelimiter', () {
    test('comma by default', () {
      expect(detectCsvDelimiter('Title,Author,ISBN'), ',');
      expect(detectCsvDelimiter('Title'), ',');
    });

    test('semicolon when the header is semicolon-separated', () {
      expect(detectCsvDelimiter('Titre;Auteur;ISBN;Editeur;Annee'), ';');
    });

    test('tab for a tab-separated export', () {
      expect(detectCsvDelimiter('Title\tPrimary Author\tISBN'), '\t');
    });
  });

  group('parseCsvLine', () {
    test('splits on the delimiter and honours quotes', () {
      expect(
        parseCsvLine('"Érasme : grandeur, décadence",Zweig,"He said ""hi"""'),
        ['Érasme : grandeur, décadence', 'Zweig', 'He said "hi"'],
      );
      expect(parseCsvLine('a;b;c', delimiter: ';'), ['a', 'b', 'c']);
    });

    test('a Goodreads armoured cell keeps its leading equals sign', () {
      // The quotes are consumed here; cleanImportedIsbn removes the "=".
      expect(parseCsvLine('x,="9782264024848",y'), ['x', '=9782264024848', 'y']);
    });
  });

  group('cleanImportedIsbn', () {
    test('an empty or missing cell is an absence, not a rejection', () {
      expect(cleanImportedIsbn(null), (isbn: null, rejected: false));
      expect(cleanImportedIsbn('  '), (isbn: null, rejected: false));
      // Goodreads writes ="" for a book without ISBN.
      expect(cleanImportedIsbn('=""'), (isbn: null, rejected: false));
      expect(cleanImportedIsbn('='), (isbn: null, rejected: false));
    });

    test('strips the Goodreads armour and formatting', () {
      expect(
        cleanImportedIsbn('="9782264024848"'),
        (isbn: '9782264024848', rejected: false),
      );
      expect(
        cleanImportedIsbn('=9782264024848'),
        (isbn: '9782264024848', rejected: false),
      );
      expect(
        cleanImportedIsbn('978-2-264-02484-8'),
        (isbn: '9782264024848', rejected: false),
      );
      expect(cleanImportedIsbn('226402484x'), (isbn: '226402484X', rejected: false));
    });

    test('reads a spreadsheet number back into its digits', () {
      expect(
        cleanImportedIsbn('9.782253140191E12'),
        (isbn: '9782253140191', rejected: false),
      );
      expect(
        cleanImportedIsbn('9782253140191.0'),
        (isbn: '9782253140191', rejected: false),
      );
    });

    test('a run of digits that is not an ISBN is rejected, not stored', () {
      // What a semicolon-separated line became once its digits were glued:
      // the ISBN followed by the year.
      expect(
        cleanImportedIsbn('Yvain;;9782070793693;Gallimard;2017'),
        (isbn: null, rejected: true),
      );
      expect(cleanImportedIsbn('12345'), (isbn: null, rejected: true));
    });
  });

  group('splitting a payload into records', () {
    test('a quoted title carrying line breaks stays one record', () {
      final records = splitCsvRecords(
        'titre;isbn\n'
        '"El Cuento\n            \n   Coleccion Popular";"9786071601933"\n'
        'Fables;9782253010043\n',
      );
      expect(records.length, 3, reason: 'header plus two records');
      expect(records[1], contains('Coleccion Popular'));
      expect(records[2], startsWith('Fables'));
    });

    test('a quote nobody closes damages its own record, not the file', () {
      // A stray double quote in a title, or a truncated download. Without a
      // bound, the rest of the file lands in one record and imports as a
      // single book whose title carries every remaining line.
      final lines = <String>['titre;auteurs;isbn', '"Le Petit Prince;Saint-Ex;978'];
      for (var i = 0; i < 40; i++) {
        lines.add('Livre $i;Auteur $i;978000000000$i');
      }
      final records = splitCsvRecords('${lines.join('\n')}\n');

      expect(
        records.length,
        greaterThan(30),
        reason: 'the file is still read after the broken record',
      );
      expect(records.last, startsWith('Livre 39'));
    });

    test('the last record needs no trailing newline', () {
      expect(splitCsvRecords('a;b\nc;d').length, 2);
    });
  });

  group('cleaning imported text', () {
    test('collapses line breaks, tabs and runs of spaces', () {
      expect(
        cleanImportedText('El Cuento\n            \n   Coleccion  Popular '),
        'El Cuento Coleccion Popular',
      );
    });

    test('a title longer than the cap is cut, a real one never is', () {
      // Measured on a real 567-book library: longest title 120 characters,
      // median 20. The cap exists for malformed files, not for books.
      final long = 'A' * 400;
      expect(
        cleanImportedText(long, maxChars: maxImportedTitleLength).length,
        maxImportedTitleLength,
      );
      const real =
          "L'Amerique latine et l'Europe a l'heure de la mondialisation. "
          'Dimensions des relations internationales';
      expect(cleanImportedText(real, maxChars: maxImportedTitleLength), real);
    });

    test('an author cell joining many names survives the cap', () {
      // Exports join every co-author into one cell; the same library carries a
      // 212 character one. Truncating it would stop it matching the value a
      // previous import stored whole.
      final many = List.generate(12, (i) => 'Prenom Nom Numero XXX').join(', ');
      expect(many.length, greaterThan(200));
      expect(
        cleanImportedTextOrNull(many, maxChars: maxImportedAuthorLength),
        many,
      );
    });

    test('the cut lands on a character boundary', () {
      // Slicing UTF-16 in the middle of a surrogate pair leaves a broken
      // character; the emoji here are two code units each.
      final emoji = '\u{1F4DA}' * 400;
      final cut = cleanImportedText(emoji, maxChars: 10);
      expect(cut.runes.length, 10);
      expect(cut, '\u{1F4DA}' * 10);
    });

    test('a cell holding only whitespace comes back null', () {
      expect(cleanImportedTextOrNull('   \n  '), isNull);
      expect(cleanImportedTextOrNull(null), isNull);
      expect(cleanImportedTextOrNull(' Hugo '), 'Hugo');
    });
  });
}
