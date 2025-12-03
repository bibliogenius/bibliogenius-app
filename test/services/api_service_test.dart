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

  group('ApiService', () {
    test('getBooks returns list of books on 200', () async {
      const route = '/api/books';
      final mockResponse = {
        'books': [
          {'id': 1, 'title': 'Test Book', 'author': 'Test Author'}
        ]
      };

      dioAdapter.onGet(
        route,
        (server) => server.reply(200, mockResponse),
      );

      final response = await apiService.getBooks();

      expect(response.statusCode, 200);
      expect(response.data, mockResponse);
    });

    test('login returns token on success', () async {
      const route = '/api/auth/login';
      final mockResponse = {'token': 'new_fake_token'};
      final data = {'username': 'user', 'password': 'password'};

      dioAdapter.onPost(
        route,
        (server) => server.reply(200, mockResponse),
        data: data,
      );

      final response = await apiService.login('user', 'password');

      expect(response.statusCode, 200);
      expect(response.data['token'], 'new_fake_token');
    });

    test('createBook sends correct data', () async {
      const route = '/api/books';
      final bookData = {'title': 'New Book', 'author': 'New Author'};
      final mockResponse = {'id': 2, ...bookData};

      dioAdapter.onPost(
        route,
        (server) => server.reply(201, mockResponse),
        data: bookData,
      );

      final response = await apiService.createBook(bookData);

      expect(response.statusCode, 201);
      expect(response.data['title'], 'New Book');
    });
    
    test('getLibraryConfig returns config', () async {
      const route = '/api/config';
      final mockResponse = {'name': 'My Library', 'profile_type': 'individual'};

      dioAdapter.onGet(
        route,
        (server) => server.reply(200, mockResponse),
      );

      final response = await apiService.getLibraryConfig();

      expect(response.statusCode, 200);
      expect(response.data['name'], 'My Library');
    });
  });
}
