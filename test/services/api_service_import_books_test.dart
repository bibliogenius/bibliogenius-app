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
}
