import 'dart:io';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

/// "Reimport to complete" (ADR-071) reads the source file a second time to fill
/// the books that are already there. It reuses the import readers with a
/// collecting sink: these tests pin that the read creates nothing, and that a
/// column the header names do not recognise can be designated by hand.
void main() {
  late Directory tmp;
  late ApiService apiService;
  late List<frb.FrbBook> created;
  late List<frb.FrbBook> read;

  const codeColumnFile =
      'Titre,Auteur,Code,Editeur,Annee\n'
      'Martin Eden,Jack London,9782264024848,10/18,1999\n'
      'Fables,Jean de La Fontaine,9782253010043,Le Livre de Poche,2002\n';

  Future<String> write(String name, String content) async {
    final file = File('${tmp.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('read_import_rows_test');
    created = [];
    read = [];
    apiService = ApiService(
      MockAuthService(),
      baseUrl: 'http://localhost:8001',
      useFfi: true,
    )..importBookSink = (book) async => created.add(book);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('a sink reads the rows and creates nothing', () async {
    final path = await write(
      'export.csv',
      'title;authors;isbn;publisher;publication_year\n'
      'Martin Eden;Jack London;9782264024848;10/18;1999\n',
    );

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
    );

    expect(response.statusCode, 200);
    expect(created, isEmpty, reason: 'a read must not add a single book');
    expect(read.length, 1);
    expect(read.first.title, 'Martin Eden');
    expect(read.first.author, 'Jack London');
    expect(read.first.isbn, '9782264024848');
    expect(read.first.publisher, '10/18');
    expect(read.first.publicationYear, 1999);
  });

  test('an unrecognised ISBN column is reported with its position', () async {
    final path = await write('code.csv', codeColumnFile);

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
    );

    expect(response.statusCode, 400);
    expect(response.data['error'], ApiService.importErrorIsbnColumnMissing);
    expect(response.data['columns'], [
      'Titre',
      'Auteur',
      'Code',
      'Editeur',
      'Annee',
    ]);
    // The caller hands one of these positions back as the column choice; the
    // list's own indices would be wrong as soon as a header is empty.
    expect(response.data['column_positions'], [0, 1, 2, 3, 4]);
    expect(read, isEmpty);
  });

  test('the designated column is the one that is read', () async {
    final path = await write('code.csv', codeColumnFile);

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
      isbnColumnIndex: 2,
    );

    expect(response.statusCode, 200);
    expect(read.map((b) => b.isbn), ['9782264024848', '9782253010043']);
    expect(created, isEmpty);
  });

  test('the position of a listed header survives an empty column', () async {
    final path = await write(
      'blank.csv',
      'Titre,,Code\nMartin Eden,,9782264024848\n',
    );

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
    );

    expect(response.statusCode, 400);
    expect(response.data['columns'], ['Titre', 'Code']);
    expect(
      response.data['column_positions'],
      [0, 2],
      reason: 'Code is the third column, whatever its rank in the list',
    );

    read.clear();
    final second = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
      isbnColumnIndex: 2,
    );
    expect(second.statusCode, 200);
    expect(read.single.isbn, '9782264024848');
  });

  test('a title carrying a line break stays one book, not two', () async {
    // A real export from a real library: the title was scraped off a web page
    // with its indentation, and the exporter quoted it faithfully. Read line by
    // line, the record was torn in two and its tail became a book of its own,
    // titled with the whole remainder, ISBN included.
    final path = await write(
      'multiline.csv',
      'titre;auteurs;isbn\n'
      '"El Cuento Hispanoamericano\n'
      '            \n'
      '                Coleccion Popular";"Seymour Menton";"9786071601933"\n'
      '"Fables";"Jean de La Fontaine";"9782253010043"\n',
    );

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
    );

    expect(response.statusCode, 200);
    expect(read.length, 2, reason: 'two records, not four fragments');
    expect(
      read.first.title,
      'El Cuento Hispanoamericano Coleccion Popular',
      reason: 'the line breaks and the indentation are collapsed',
    );
    expect(read.first.author, 'Seymour Menton');
    expect(read.first.isbn, '9786071601933');
  });

  test('a designated column that is out of range falls back to the lookup',
      () async {
    final path = await write(
      'ean.csv',
      'Titre,Auteur,EAN\nMartin Eden,Jack London,9782264024848\n',
    );

    final response = await apiService.importBooks(
      path,
      sink: (book) async => read.add(book),
      isbnColumnIndex: 99,
    );

    expect(response.statusCode, 200);
    expect(read.single.isbn, '9782264024848');
  });
}
