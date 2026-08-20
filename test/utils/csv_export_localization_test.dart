import 'dart:convert';

import 'package:bibliogenius/utils/backup_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rewrite runs on the bytes the Rust exporter produced, so these tests
/// feed it exactly what `api::export::export_catalog_csv` emits: a UTF-8 BOM,
/// a `;`-delimited header row of stable English names, then data rows whose
/// possession and reading-status cells hold stable English tokens.
void main() {
  const bom = [0xEF, 0xBB, 0xBF];
  const englishHeader =
      'title;authors;isbn;publisher;publication_year;language;'
      'ownership_status;reading_status;user_rating;price;tags;added_at';

  /// French labels, keyed by the English column name the core writes.
  const frenchHeader = {
    'title': 'titre',
    'authors': 'auteurs',
    'isbn': 'isbn',
    'publisher': 'éditeur',
    'publication_year': 'année de publication',
    'language': 'langue',
    'ownership_status': 'possession',
    'reading_status': 'statut de lecture',
    'user_rating': 'note',
    'price': 'prix',
    'tags': 'étiquettes',
    'added_at': "date d'ajout",
  };
  const frenchHeaderRow = [
    'titre',
    'auteurs',
    'isbn',
    'éditeur',
    'année de publication',
    'langue',
    'possession',
    'statut de lecture',
    'note',
    'prix',
    'étiquettes',
    "date d'ajout",
  ];

  const frenchValues = {
    'ownership_status': {
      'owned': 'Dans ma bibliothèque',
      'borrowed': 'Emprunté',
      'wishlist': 'Souhaité',
    },
    'reading_status': {
      'to_read': 'À lire',
      'reading': 'En cours',
      'read': 'Lu',
      'wanting': 'Envie de lire',
      'abandoned': 'Abandonné',
    },
  };

  List<int> exportBytes(String body) => [...bom, ...utf8.encode(body)];

  String decode(List<int> bytes) {
    expect(bytes.sublist(0, 3), bom, reason: 'the BOM must survive');
    return utf8.decode(bytes.sublist(3));
  }

  Map<String, String> genericHeader(String prefix) => {
    for (var i = 0; i < BackupActions.csvColumnNames.length; i++)
      BackupActions.csvColumnNames[i]: '$prefix$i',
  };

  List<int> localize(
    List<int> bytes, {
    Map<String, String>? headerLabels,
    Map<String, Map<String, String>> valueLabels = const {},
  }) => BackupActions.localizeCsv(
    bytes,
    headerLabels: headerLabels ?? frenchHeader,
    valueLabels: valueLabels,
  );

  group('catalogueCsvFilename', () {
    test('stamps the local date and time down to the minute', () {
      expect(
        BackupActions.catalogueCsvFilename(DateTime(2026, 8, 20, 14, 14)),
        'bibliogenius_catalogue_2026-08-20_14-14.csv',
      );
    });

    test('pads single digits so names sort chronologically', () {
      expect(
        BackupActions.catalogueCsvFilename(DateTime(2026, 1, 5, 9, 7)),
        'bibliogenius_catalogue_2026-01-05_09-07.csv',
      );
    });

    test('two exports a minute apart do not collide', () {
      // The point of the stamp: overwriting a file a spreadsheet still has
      // open leaves the user reading the previous import.
      final first = BackupActions.catalogueCsvFilename(
        DateTime(2026, 8, 20, 12, 1),
      );
      final second = BackupActions.catalogueCsvFilename(
        DateTime(2026, 8, 20, 14, 14),
      );
      expect(first, isNot(second));
    });

    test('never uses a character Windows forbids in a filename', () {
      final name = BackupActions.catalogueCsvFilename(
        DateTime(2026, 8, 20, 14, 14),
      );
      for (final forbidden in [':', '/', '\\', '?', '*', '<', '>', '|', '"']) {
        expect(name, isNot(contains(forbidden)));
      }
    });
  });

  group('localizeCsv header', () {
    test('replaces the header row and leaves the data rows untouched', () {
      final bytes = exportBytes(
        '$englishHeader\nLes Misérables;Hugo, Victor;;;1862;fr;'
        'owned;read;9;;classiques;2026-08-20\n',
      );

      final rows = _parseCsv(decode(localize(bytes)));
      expect(rows.first, frenchHeaderRow);
      // No value map passed: the tokens stay as the core wrote them.
      expect(rows[1], [
        'Les Misérables',
        'Hugo, Victor',
        '',
        '',
        '1862',
        'fr',
        'owned',
        'read',
        '9',
        '',
        'classiques',
        '2026-08-20',
      ]);
    });

    test('quotes a label containing the delimiter or a quote', () {
      final bytes = exportBytes('$englishHeader\nA;;;;;;owned;read;;;;\n');
      final header = genericHeader('col')
        ..['title'] = 'titre; sous-titre'
        ..['authors'] = 'auteur "principal"';

      final text = decode(localize(bytes, headerLabels: header));
      final firstLine = text.split('\n').first;
      expect(
        firstLine,
        startsWith('"titre; sous-titre";"auteur ""principal""";'),
      );
      expect(_parseCsvRow(firstLine)[0], 'titre; sous-titre');
      expect(_parseCsvRow(firstLine)[1], 'auteur "principal"');
      expect(
        _parseCsvRow(firstLine).length,
        BackupActions.csvColumnNames.length,
      );
    });

    test('leaves a file whose columns it recognizes none of untouched', () {
      // Not our export: better to hand back what we were given than to relabel
      // somebody else's file.
      final bytes = exportBytes('alpha;beta;gamma\n1;2;3\n');
      expect(localize(bytes, valueLabels: frenchValues), bytes);
    });

    test('translates a column set the core trimmed, by name not position', () {
      // The core drops `price` when the commerce module is off, which shifts
      // every column after it. Nothing may be located by index.
      const trimmed =
          'title;authors;isbn;publisher;publication_year;language;'
          'ownership_status;reading_status;user_rating;tags;added_at';
      final bytes = exportBytes(
        '$trimmed\n"Les Misérables";"Hugo, Victor";;;1862;fr;'
        '"owned";"read";9;"classiques";2026-08-20\n',
      );

      final rows = _parseCsv(
        decode(localize(bytes, valueLabels: frenchValues)),
      );
      expect(rows.first, [
        'titre',
        'auteurs',
        'isbn',
        'éditeur',
        'année de publication',
        'langue',
        'possession',
        'statut de lecture',
        'note',
        'étiquettes',
        "date d'ajout",
      ]);
      expect(rows[1][6], 'Dans ma bibliothèque');
      expect(rows[1][7], 'Lu');
      expect(rows[1][9], 'classiques');
    });

    test('keeps an unknown column under its original name', () {
      // A core newer than this build: translate what we know, pass the rest
      // through rather than dropping or mislabelling it.
      final bytes = exportBytes('title;something_new\n"A";"B"\n');
      final rows = _parseCsv(
        decode(localize(bytes, valueLabels: frenchValues)),
      );
      expect(rows.first, ['titre', 'something_new']);
      expect(rows[1], ['A', 'B']);
    });

    test('leaves a headerless (empty) payload untouched', () {
      final bytes = exportBytes('');
      expect(localize(bytes), bytes);
    });

    test('handles a file with a header row and no data rows', () {
      final bytes = exportBytes('$englishHeader\n');
      expect(
        decode(localize(bytes, headerLabels: genericHeader('col'))),
        '"col0";"col1";"col2";"col3";"col4";"col5";"col6";"col7";"col8";'
        '"col9";"col10";"col11"\n',
      );
    });

    test('exposes one i18n key per exported column', () {
      expect(
        BackupActions.csvColumnNames.length,
        englishHeader.split(';').length,
      );
      expect(
        BackupActions.csvColumnNames.toSet().length,
        BackupActions.csvColumnNames.length,
      );
    });
  });

  group('localizeCsv values', () {
    test('translates the possession and reading-status cells', () {
      final bytes = exportBytes(
        '$englishHeader\n'
        'A;;;;;;owned;read;;;;2026-08-20\n'
        'B;;;;;;borrowed;reading;;;;2026-08-20\n'
        'C;;;;;;wishlist;wanting;;;;2026-08-20\n'
        'D;;;;;;owned;abandoned;;;;2026-08-20\n'
        'E;;;;;;owned;to_read;;;;2026-08-20\n',
      );

      final rows = decode(
        localize(bytes, valueLabels: frenchValues),
      ).trim().split('\n').map(_parseCsvRow).toList();

      expect(rows[1][6], 'Dans ma bibliothèque');
      expect(rows[1][7], 'Lu');
      expect(rows[2][6], 'Emprunté');
      expect(rows[2][7], 'En cours');
      expect(rows[3][6], 'Souhaité');
      expect(rows[3][7], 'Envie de lire');
      expect(rows[4][7], 'Abandonné');
      expect(rows[5][7], 'À lire');
    });

    test('leaves an unknown status token alone rather than blanking it', () {
      // `reading_status` can hold a value the service-layer gate never saw:
      // account-sync replication and direct repository writes both bypass it.
      final bytes = exportBytes(
        '$englishHeader\nA;;;;;;owned;some_future_status;;;;\n',
      );
      final row = _parseCsvRow(
        decode(localize(bytes, valueLabels: frenchValues)).split('\n')[1],
      );
      expect(row[7], 'some_future_status');
      expect(row[6], 'Dans ma bibliothèque');
    });

    test('leaves an empty status cell empty', () {
      final bytes = exportBytes('$englishHeader\nA;;;;;;owned;;;;;\n');
      final row = _parseCsvRow(
        decode(localize(bytes, valueLabels: frenchValues)).split('\n')[1],
      );
      expect(row[7], '');
    });

    test('only touches the columns it was given', () {
      // "read" is also a plausible word in a title or a tag; only the
      // reading_status column may be rewritten.
      final bytes = exportBytes(
        '$englishHeader\nread;;;;;;owned;read;;;read;\n',
      );
      final row = _parseCsvRow(
        decode(localize(bytes, valueLabels: frenchValues)).split('\n')[1],
      );
      expect(row[0], 'read', reason: 'title must not be translated');
      expect(row[10], 'read', reason: 'tags must not be translated');
      expect(row[7], 'Lu');
    });
  });

  group('localizeCsv quoting', () {
    test('keeps a cell holding a comma in one column', () {
      // The regression this guards: re-emitting the file with the laxer
      // "quote only what a ;-reader needs" rule stripped the quotes the core
      // put around `Hugo, Victor`, and LibreOffice split it in two.
      final bytes = exportBytes(
        '$englishHeader\n"Le Horla";"Maupassant, Guy de";;;;;'
        '"owned";"read";;;"romans, classiques";\n',
      );

      final text = decode(localize(bytes, valueLabels: frenchValues));
      expect(text, contains('"Maupassant, Guy de"'));
      expect(text, contains('"romans, classiques"'));

      final row = _parseCsv(text)[1];
      expect(row.length, BackupActions.csvColumnNames.length);
      expect(row[1], 'Maupassant, Guy de');
      expect(row[10], 'romans, classiques');
    });

    test('leaves numbers bare so the spreadsheet sorts them as numbers', () {
      final bytes = exportBytes(
        '$englishHeader\n"A";;;;1862;;"owned";"read";9;12.5;;\n',
      );
      final text = decode(localize(bytes, valueLabels: frenchValues));
      final dataLine = text.split('\n')[1];
      expect(dataLine, contains(';1862;'));
      expect(dataLine, contains(';9;12.5;'));
    });
  });

  group('localizeCsv round-trip', () {
    test('keeps the core formula defusing intact', () {
      // The core prefixes a cell a spreadsheet would execute (CWE-1236). The
      // rewrite must carry that apostrophe through: stripping it would hand
      // the user back a live formula planted by a peer or a metadata source.
      final bytes = exportBytes(
        '$englishHeader\n'
        '"\'=HYPERLINK(""http://evil"",""click"")";"\'=cmd|\'/c calc\'!A0";;;;;'
        '"owned";"read";;;;\n',
      );

      final row = _parseCsv(
        decode(localize(bytes, valueLabels: frenchValues)),
      )[1];
      expect(row[0], startsWith("'="));
      expect(row[1], startsWith("'="));
    });

    test('preserves a field carrying a delimiter, a quote and a newline', () {
      // The exporter quotes such a title; parsing and re-emitting it must give
      // the same value back, not a split row.
      const nasty = 'Ainsi; parla "Zarathoustra"\nou presque';
      final bytes = exportBytes(
        '$englishHeader\n'
        '"Ainsi; parla ""Zarathoustra""\nou presque";Nietzsche;;;;;'
        'owned;read;;;;2026-08-20\n',
      );

      final text = decode(localize(bytes, valueLabels: frenchValues));
      final rows = _parseCsv(text);
      expect(rows.length, 2, reason: 'the quoted newline split the row');
      expect(rows[1][0], nasty);
      expect(rows[1][1], 'Nietzsche');
      expect(rows[1][7], 'Lu');
    });

    test('leaves a payload with an unterminated quote untouched', () {
      // Not the file we think it is: rewriting it would corrupt it.
      final bytes = exportBytes(
        '$englishHeader\n"never closed;;;;;;owned;read\n',
      );
      expect(localize(bytes, valueLabels: frenchValues), bytes);
    });

    test('keeps a file that does not end on a newline unterminated', () {
      final bytes = exportBytes('$englishHeader\nA;;;;;;owned;read;;;;');
      final text = decode(localize(bytes, valueLabels: frenchValues));
      expect(text.endsWith('\n'), isFalse);
      expect(_parseCsv(text).length, 2);
    });
  });
}

/// Minimal `;`-delimited CSV reader, independent from the implementation under
/// test, so a bug in the production parser cannot hide behind itself.
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var fields = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (char == '"') {
        inQuotes = false;
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"') {
      inQuotes = true;
    } else if (char == ';') {
      fields.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      fields.add(field.toString());
      field.clear();
      rows.add(fields);
      fields = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || fields.isNotEmpty) {
    fields.add(field.toString());
    rows.add(fields);
  }
  return rows;
}

List<String> _parseCsvRow(String row) => _parseCsv(row).first;
