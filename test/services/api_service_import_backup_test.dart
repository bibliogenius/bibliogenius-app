import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';

class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

/// A catalogue exported before the uuid primary keys carries integer ids, which
/// the core refuses with a 422 naming the offending field. `importBackup` used
/// to catch that alongside a genuinely unreadable file and report both as
/// "Failed to parse backup file", so the reason never reached the user.
void main() {
  const route = '/api/import';
  late Dio dio;
  late DioAdapter dioAdapter;
  late ApiService apiService;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8001'));
    dioAdapter = DioAdapter(dio: dio);
    apiService = ApiService(
      MockAuthService(),
      dio: dio,
      baseUrl: 'http://localhost:8001',
    );
  });

  group('ApiService.importBackup failure reporting', () {
    test('a file that is not JSON is reported as unreadable, not as a '
        'server failure', () async {
      final response = await apiService.importBackup(
        utf8.encode('this is not a backup'),
      );

      expect(response.statusCode, 400);
      expect(response.data['error'], 'unreadable_file');
      expect(response.data['detail'], isNotEmpty);
      // FormatException prints the offending source line under its message.
      expect(response.data['detail'], isNot(contains('not a backup')));
    });

    test('a 422 from the core is reported as an incompatible backup, '
        'carrying the reason it gave', () async {
      final backup = {'version': '2.0', 'books': []};
      dioAdapter.onPost(
        route,
        (server) => server.reply(
          422,
          'Failed to deserialize the JSON body into the target type: '
              'books[0].id: invalid type: integer `12`, expected a string',
        ),
        data: backup,
      );

      final response = await apiService.importBackup(
        utf8.encode(jsonEncode(backup)),
      );

      expect(response.statusCode, 422);
      expect(response.data['error'], 'incompatible_backup');
      expect(response.data['detail'], contains('expected a string'));
    });

    test('any other server status keeps its code and its body', () async {
      final backup = {'version': '2.0', 'books': []};
      dioAdapter.onPost(
        route,
        (server) => server.reply(500, {'error': 'Failed to wipe catalog'}),
        data: backup,
      );

      final response = await apiService.importBackup(
        utf8.encode(jsonEncode(backup)),
      );

      expect(response.statusCode, 500);
      expect(response.data['error'], 'server_error');
      expect(response.data['detail'], contains('Failed to wipe catalog'));
    });

    // A transport failure carries no response, so it must not be read as the
    // core refusing the payload. `DioExceptionType.unknown` keeps the test off
    // the RetryInterceptor's healing path, which probes local ports and would
    // make the outcome depend on whatever runs on the machine.
    test('a transport failure is reported as a network failure', () async {
      final backup = {'version': '2.0', 'books': []};
      dioAdapter.onPost(
        route,
        (server) => server.throws(
          0,
          DioException(
            requestOptions: RequestOptions(path: route),
            type: DioExceptionType.unknown,
            error: 'socket closed',
          ),
        ),
        data: backup,
      );

      final response = await apiService.importBackup(
        utf8.encode(jsonEncode(backup)),
      );

      expect(response.data['error'], 'network_error');
    });

    test('a successful import is passed through untouched', () async {
      final backup = {'version': '2.0', 'books': []};
      dioAdapter.onPost(
        route,
        (server) => server.reply(200, {'success': true, 'books_imported': 23}),
        data: backup,
      );

      final response = await apiService.importBackup(
        utf8.encode(jsonEncode(backup)),
      );

      expect(response.statusCode, 200);
      expect(response.data['books_imported'], 23);
    });
  });

  group('ApiService.redactImportDetail', () {
    test('drops the value the core quotes back, keeps the field path', () {
      final redacted = ApiService.redactImportDetail(
        'Failed to deserialize the JSON body into the target type: '
        'contacts[3].email: invalid type: string "someone@example.com", '
        'expected an integer',
      );

      expect(redacted, contains('contacts[3].email'));
      expect(redacted, contains('expected an integer'));
      expect(redacted, isNot(contains('someone@example.com')));
    });

    test('drops a value quoted with backticks', () {
      final redacted = ApiService.redactImportDetail(
        'books[0].id: invalid type: integer `12`, expected a string',
      );

      expect(redacted, contains('books[0].id'));
      expect(redacted, isNot(contains('12')));
    });

    test('keeps only the first line, where a FormatException puts its '
        'message and not the file content', () {
      final redacted = ApiService.redactImportDetail(
        'FormatException: Unexpected character (at character 3)\n'
        '{"title": "Le nom de la rose", "isbn": "9782253033134"}\n'
        '  ^',
      );

      expect(redacted, 'FormatException: Unexpected character (at character 3)');
    });

    test('caps a long body', () {
      final redacted = ApiService.redactImportDetail('x' * 1000);

      expect(redacted.length, lessThan(1000));
      expect(redacted, endsWith('...'));
    });

    test('leaves a short unquoted message alone', () {
      const detail = 'Failed to wipe existing catalog';

      expect(ApiService.redactImportDetail(detail), detail);
    });
  });
}
