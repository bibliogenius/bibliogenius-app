import 'dart:convert';
import 'dart:io';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

/// The native import parses the CSV itself and creates books one by one. It
/// once imported a 2861-book library without a single ISBN and reported
/// success: the ISBN column was named EAN, so it was never read. These tests
/// pin the four files that reproduced the family of defects by hand.
void main() {
  late Directory tmp;
  late ApiService apiService;
  late List<frb.FrbBook> created;

  const eanFile =
      'Titre,Auteur,EAN,Editeur,Annee\n'
      'Martin Eden,Jack London,9782264024848,10/18,1999\n'
      'Fables,Jean de La Fontaine,9782253010043,Le Livre de Poche,2002\n'
      '"Érasme : grandeur et décadence d\'une idée",Stefan Zweig,9782253140191,Le Livre de Poche,2000\n'
      'Yvain ou Le chevalier au lion,,9782070793693,Gallimard,2017\n';

  Future<String> write(String name, String content) async {
    final file = File('${tmp.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_books_test');
    created = [];
    // `baseUrl` keeps the constructor away from dotenv, which is not loaded
    // in a unit test.
    apiService = ApiService(
      MockAuthService(),
      baseUrl: 'http://localhost:8001',
      useFfi: true,
    )..importBookSink = (book) async => created.add(book);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('a file whose ISBN column is not recognised', () {
    test('is not imported until the reader agrees, and says which columns '
        'were read', () async {
      final path = await write(
        'no-isbn.csv',
        'Titre,Auteur,Editeur\nMartin Eden,Jack London,10/18\n',
      );

      final response = await apiService.importBooks(path);

      expect(response.statusCode, 400);
      expect(response.data['error'], ApiService.importErrorIsbnColumnMissing);
      expect(response.data['columns'], ['Titre', 'Auteur', 'Editeur']);
      expect(created, isEmpty);
    });

    test('imports without ISBN once allowed, and reports none carried one',
        () async {
      final path = await write(
        'no-isbn.csv',
        'Titre,Auteur,Editeur\nMartin Eden,Jack London,10/18\n',
      );

      final response = await apiService.importBooks(
        path,
        allowMissingIsbn: true,
      );

      expect(response.statusCode, 200);
      expect(response.data['imported'], 1);
      expect(response.data['with_isbn'], 0);
      expect(created.single.isbn, isNull);
      expect(created.single.title, 'Martin Eden');
    });
  });

  group('the EAN column of a French export', () {
    test('is the ISBN column, so nothing is lost', () async {
      final path = await write('ean.csv', eanFile);

      final response = await apiService.importBooks(path);

      expect(response.statusCode, 200);
      expect(response.data['imported'], 4);
      expect(response.data['with_isbn'], 4);
      expect(response.data['rejected_isbn'], 0);
      expect(created.map((b) => b.isbn), [
        '9782264024848',
        '9782253010043',
        '9782253140191',
        '9782070793693',
      ]);
      expect(created[2].title, "Érasme : grandeur et décadence d'une idée");
      expect(created[3].author, isNull);
      expect(created[3].publicationYear, 2017);
    });
  });

  group('a semicolon-separated file', () {
    test('is split on semicolons instead of landing whole in every field',
        () async {
      final path = await write('semicolon.csv', eanFile.replaceAll(',', ';'));

      final response = await apiService.importBooks(path);

      expect(response.statusCode, 200);
      expect(response.data['with_isbn'], 4);
      expect(created.first.title, 'Martin Eden');
      expect(created.first.author, 'Jack London');
      expect(created.first.isbn, '9782264024848');
      expect(created.first.publisher, '10/18');
      expect(created.first.publicationYear, 1999);
    });
  });

  group('a Goodreads export', () {
    test('loses the ="..." armour, prefers ISBN13, and stores nothing for '
        '=""', () async {
      final path = await write(
        'goodreads.csv',
        'Title,Author,ISBN,ISBN13,Publisher,Year Published\n'
        'Martin Eden,Jack London,="2264024844",="9782264024848",10/18,1999\n'
        'Fables,Jean de La Fontaine,="",="",Le Livre de Poche,2002\n',
      );

      final response = await apiService.importBooks(path);

      expect(response.statusCode, 200);
      expect(response.data['imported'], 2);
      expect(response.data['with_isbn'], 1);
      expect(response.data['rejected_isbn'], 0);
      expect(created[0].isbn, '9782264024848');
      expect(created[1].isbn, isNull);
    });
  });

  group('an ISBN cell that is not an ISBN', () {
    test('is dropped and counted, never stored as a run of digits', () async {
      final path = await write(
        'garbage.csv',
        'Title,Author,ISBN\nYvain,Chrétien de Troyes,97820707936932017\n',
      );

      final response = await apiService.importBooks(path);

      expect(response.statusCode, 200);
      expect(response.data['imported'], 1);
      expect(response.data['with_isbn'], 0);
      expect(response.data['rejected_isbn'], 1);
      expect(created.single.isbn, isNull);
    });
  });

  group('a Babelio export', () {
    // Shaped like the real "Biblio_export": semicolons, quoted cells, CRLF,
    // Windows-1252, authors surname first, a 0 to 5 rating where 0.0 is none.
    const babelio =
        '"ISBN";"Titre";"Auteur";"Editeur";"Date de publication";'
        '"Date d`entrée dans Babelio";"Statut";"Note"\r\n'
        '"9782359251012";"La démocratie aux champs";"Zask Joëlle";'
        '"Les Empêcheurs de penser en rond";"2016-02-11";'
        '"2024-06-09 19:07:24";"Lu";"4.5"\r\n'
        '"9782290430033";"De nos blessures un royaume";"Josse Gaëlle";'
        '"J\'ai lu";"0000-00-00";"2026-09-05 13:41:30";"A lire";"0.0"\r\n'
        '"9782070360024";"L\'étranger";"Camus Albert";"Folio";"1972-01-01";'
        '"2024-06-09 19:07:24";"Pense-bête";"0.0"\r\n';

    late List<frb.FrbBook> books;

    setUp(() async {
      final file = File('${tmp.path}/Biblio_export.csv');
      await file.writeAsBytes(latin1.encode(babelio));
      final response = await apiService.importBooks(file.path);
      expect(response.statusCode, 200, reason: '${response.data}');
      expect(response.data['source'], 'babelio');
      expect(response.data['with_reading'], 3);
      books = created;
    });

    test('is read despite its Windows-1252 encoding', () {
      expect(books.map((b) => b.title), [
        'La démocratie aux champs',
        'De nos blessures un royaume',
        "L'étranger",
      ]);
      expect(books.first.publisher, 'Les Empêcheurs de penser en rond');
    });

    test('authors arrive given name first', () {
      expect(books.map((b) => b.author), [
        'Joëlle Zask',
        'Gaëlle Josse',
        'Albert Camus',
      ]);
    });

    test('carries the reading status and the rating, out of 10', () {
      expect(books.map((b) => b.readingStatus), ['read', 'to_read', 'wanting']);
      expect(books.map((b) => b.userRating), [9, null, null]);
    });

    test('a "Pense-bête" book is a wish, not a book on the shelf', () {
      expect(books.map((b) => b.owned), [true, true, false]);
    });

    test('takes the year out of the publication date, none from 0000', () {
      expect(books.map((b) => b.publicationYear), [2016, null, 1972]);
    });

    test('never turns the Babelio entry date into a reading date', () {
      expect(books.map((b) => b.finishedReadingAt), everyElement(isNull));
      expect(books.map((b) => b.startedReadingAt), everyElement(isNull));
    });
  });

  test('a Goodreads export carries its shelf, rating and dates', () async {
    final file = File('${tmp.path}/goodreads_library_export.csv');
    await file.writeAsString(
      'Title,Author,ISBN13,My Rating,Average Rating,Date Read,Date Added,'
      'Exclusive Shelf\n'
      'Martin Eden,Jack London,="9782264024848",4,4.12,2024/06/09,'
      '2023/01/02,read\n'
      'Fables,Jean de La Fontaine,="9782253010043",0,3.9,,2023/01/02,'
      'currently-reading\n',
    );
    final response = await apiService.importBooks(file.path);
    expect(response.data['source'], 'goodreads');
    expect(created.map((b) => b.readingStatus), ['read', 'reading']);
    expect(created.map((b) => b.userRating), [8, null]);
    expect(created.first.finishedReadingAt, '2024-06-09T00:00:00.000');
    // Not reversed: Goodreads writes given name first.
    expect(created.last.author, 'Jean de La Fontaine');
  });
}
