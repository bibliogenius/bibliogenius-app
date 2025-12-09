
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:app/services/api_service.dart';
import 'package:app/services/auth_service.dart';

// Simple mock for AuthService
class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late ApiService apiService;
  late MockAuthService mockAuthService;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8001'));
    dioAdapter = DioAdapter(dio: dio);
    mockAuthService = MockAuthService();
    apiService = ApiService(mockAuthService, dio: dio, baseUrl: 'http://localhost:8001');
  });

  group('ApiService Search', () {
    test('searchBooks returns list of books on 200', () async {
      const route = '/api/integrations/search_unified';
      final query = 'test';
      final mockResponse = [
        {'id': 1, 'title': 'Test Book', 'author': 'Test Author', 'isbn': '1234567890'},
        {'id': 2, 'title': 'Another Book', 'author': 'Another Author', 'isbn': '0987654321'}
      ];

      dioAdapter.onGet(
        route,
        (server) => server.reply(200, mockResponse),
        queryParameters: {'q': query},
      );

      final response = await apiService.searchBooks(query: query);

      expect(response, isA<List>());
      expect(response.length, 2);
      expect(response[0]['title'], 'Test Book');
    });

    test('searchBooks handles empty results', () async {
      const route = '/api/integrations/search_unified';
      final query = 'nonexistent';
      final mockResponse = [];

      dioAdapter.onGet(
        route,
        (server) => server.reply(200, mockResponse),
        queryParameters: {'q': query},
      );

      final response = await apiService.searchBooks(query: query);

      expect(response, isEmpty);
    });
  });
}
