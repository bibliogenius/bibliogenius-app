import 'package:dio/dio.dart';
import 'auth_service.dart';

class ApiService {
  final Dio _dio = Dio();
  final AuthService _authService;
  // Use localhost for Web/Desktop
  // Use 10.0.2.2 for Android Emulator
  // Use your machine's IP for real device
  static const String baseUrl = 'http://localhost:8001';

  ApiService(this._authService) {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  Future<Response> login(String username, String password) async {
    return await _dio.post(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
  }

  Future<Response> getBooks() async {
    return await _dio.get('/api/books');
  }

  Future<Response> createBook(Map<String, dynamic> bookData) async {
    return await _dio.post('/api/books', data: bookData);
  }

  Future<Response> updateBook(int id, Map<String, dynamic> bookData) async {
    return await _dio.put('/api/books/$id', data: bookData);
  }

  // Copy management
  Future<Response> getBookCopies(int bookId) async {
    return await _dio.get('/api/books/$bookId/copies');
  }

  Future<Response> createCopy(Map<String, dynamic> copyData) async {
    return await _dio.post('/api/copies', data: copyData);
  }

  Future<Response> updateCopy(int id, Map<String, dynamic> copyData) async {
    return await _dio.put('/api/copies/$id', data: copyData);
  }

  // Contact methods
  Future<Response> getContacts({int? libraryId, String? type}) async {
    Map<String, dynamic> params = {};
    if (libraryId != null) params['library_id'] = libraryId;
    if (type != null) params['type'] = type;
    return await _dio.get('/api/contacts', queryParameters: params);
  }

  Future<Response> getContact(int id) async {
    return await _dio.get('/api/contacts/$id');
  }

  Future<Response> createContact(Map<String, dynamic> contactData) async {
    return await _dio.post('/api/contacts', data: contactData);
  }

  Future<Response> updateContact(
    int id,
    Map<String, dynamic> contactData,
  ) async {
    return await _dio.put('/api/contacts/$id', data: contactData);
  }

  Future<Response> deleteContact(int id) async {
    return await _dio.delete('/api/contacts/$id');
  }

  Future<Response> deleteCopy(int copyId) async {
    return await _dio.delete('/api/copies/$copyId');
  }

  // Peer methods
  Future<Response> connectPeer(String name, String url) async {
    return await _dio.post(
      '/api/peers/connect',
      data: {'name': name, 'url': url},
    );
  }

  Future<Response> getLibraryConfig() async {
    return await _dio.get('/api/config');
  }

  // Gamification
  Future<Response> getUserStatus() async {
    return await _dio.get('/api/user/status');
  }

  // Export
  Future<Response> exportData() async {
    return await _dio.get(
      '/api/export',
      options: Options(responseType: ResponseType.bytes),
    );
  }
}
