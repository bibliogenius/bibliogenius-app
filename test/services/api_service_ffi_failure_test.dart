import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

// The FFI book writes answer a backend exception with a synthetic 500. The
// cause must travel in the response: it is the only trace a release build
// keeps, and the message the user sees is built from it. The FFI singleton
// cannot be injected, so the helper behind the three catch sites is
// exercised directly.
void main() {
  late ApiService api;

  setUp(() {
    // An explicit base URL keeps the constructor off dotenv, unloaded here.
    api = ApiService(
      _MockAuthService(),
      baseUrl: 'http://127.0.0.1:8000',
      dio: Dio(),
      useFfi: true,
    );
  });

  test('ffiFailure answers a 500 carrying the cause', () {
    final response = api.ffiFailure(
      'updateBook',
      '/api/books/42',
      Exception('database is locked'),
    );
    expect(response.statusCode, 500);
    expect(response.requestOptions.path, '/api/books/42');
    expect(response.statusMessage, 'Exception: database is locked');
  });
}
