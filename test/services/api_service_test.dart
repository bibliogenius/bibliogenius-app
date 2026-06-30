import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/models/book.dart';

// Simple mock for AuthService
class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

// In-memory secure storage so the createCopy self-heal tests can seed and observe
// the cached library_id. createCopy reads it through `AuthService()` (which uses
// the static `AuthService.storage`), not the injected AuthService, so we swap the
// static backend rather than the instance.
class _InMemorySecureStorage implements SecureStorageInterface {
  final Map<String, String> store;
  _InMemorySecureStorage([Map<String, String>? initial])
    : store = {...?initial};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<String?> read({required String key}) async => store[key];

  @override
  Future<void> delete({required String key}) async => store.remove(key);
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
    apiService = ApiService(
      mockAuthService,
      dio: dio,
      baseUrl: 'http://localhost:8001',
    );
  });

  group('ApiService', () {
    test('getBooks returns list of books on 200', () async {
      const route = '/api/books';
      final mockResponse = {
        'books': [
          {'id': 1, 'title': 'Test Book', 'author': 'Test Author'},
        ],
      };

      dioAdapter.onGet(route, (server) => server.reply(200, mockResponse));

      final books = await apiService.getBooks();

      expect(books, isA<List<Book>>());
      expect(books.length, 1);
      expect(books[0].title, 'Test Book');
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

      dioAdapter.onGet(route, (server) => server.reply(200, mockResponse));

      final response = await apiService.getLibraryConfig();

      expect(response.statusCode, 200);
      expect(response.data['name'], 'My Library');
    });
  });

  group('ApiService createCopy library_id self-heal', () {
    late SecureStorageInterface originalStorage;
    setUp(() => originalStorage = AuthService.storage);
    tearDown(() => AuthService.storage = originalStorage);

    // A /api/copies POST that rejects any non-null library_id with
    // 400 "library <id> does not exist" and accepts a null one with 201 (the
    // backend-resolved path). `seen` records the library_id of each attempt.
    ApiService buildApi(List<dynamic> seen) {
      final localDio = Dio(BaseOptions(baseUrl: 'http://localhost:8001'));
      localDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/api/copies' && options.method == 'POST') {
              final libId = (options.data as Map)['library_id'];
              seen.add(libId);
              if (libId != null) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 400,
                      data: {'error': 'library $libId does not exist'},
                    ),
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 201,
                    data: {'id': 'copy-uuid', 'library_id': 1},
                  ),
                );
              }
              return;
            }
            handler.next(options);
          },
        ),
      );
      return ApiService(
        MockAuthService(),
        dio: localDio,
        baseUrl: 'http://localhost:8001',
      );
    }

    test('clears a stale cached id and retries with null on '
        '"library does not exist"', () async {
      AuthService.storage = _InMemorySecureStorage({'library_id': '16'});
      final seen = <dynamic>[];
      final api = buildApi(seen);

      final response = await api.createCopy({
        'book_id': 'book-uuid',
        'status': 'available',
      });

      expect(response.statusCode, 201);
      expect(
        seen,
        [16, null],
        reason: 'first attempt sends the stale 16, the retry sends null',
      );
      expect(
        await AuthService().getLibraryId(),
        isNull,
        reason: 'the stale cached library_id must be cleared',
      );
    });

    test('does not retry or clear the cache on an unrelated 400', () async {
      AuthService.storage = _InMemorySecureStorage({'library_id': '16'});
      final seen = <dynamic>[];
      final localDio = Dio(BaseOptions(baseUrl: 'http://localhost:8001'));
      localDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/api/copies' && options.method == 'POST') {
              seen.add((options.data as Map)['library_id']);
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: {'error': 'some other validation error'},
                  ),
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );
      final api = ApiService(
        MockAuthService(),
        dio: localDio,
        baseUrl: 'http://localhost:8001',
      );

      await expectLater(
        api.createCopy({'book_id': 'book-uuid', 'status': 'available'}),
        throwsA(isA<DioException>()),
      );
      expect(seen, [16], reason: 'no retry on an unrelated error');
      expect(
        await AuthService().getLibraryId(),
        16,
        reason: 'an unrelated 400 must NOT clear the cached library_id',
      );
    });
  });
}
