import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';

class ApiService {
  final Dio _dio;
  final AuthService _authService;
  
  // Read from .env with fallback to localhost
  static String get defaultBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8001';
  static String get hubUrl => dotenv.env['HUB_URL'] ?? 'http://localhost:8081';

  ApiService(this._authService, {String? baseUrl, Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = baseUrl ?? defaultBaseUrl;
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

  void updatePort(int port) {
    _dio.options.baseUrl = 'http://localhost:$port';
    debugPrint('ApiService updated to use port $port');
  }

  String get baseUrl => _dio.options.baseUrl;

  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
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

  Future<Response> deleteBook(int id) async {
    return await _dio.delete('/api/books/$id');
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

  // Loan methods
  Future<Response> createLoan(Map<String, dynamic> loanData) async {
    return await _dio.post('/api/loans', data: loanData);
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
      '$hubUrl/api/peers/connect',
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

  Future<Response> importBooks(String filePath) async {
    String fileName = filePath.split('/').last;
    FormData formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(filePath, filename: fileName),
    });
    return await _dio.post('/api/import/file', data: formData);
  }

  // P2P Advanced
  Future<Response> getPeers() async {
    return await _dio.get('$hubUrl/api/peers');
  }

  Future<Response> searchPeers(String query) async {
    return await _dio.get('$hubUrl/api/peers/search', queryParameters: {'q': query});
  }

  Future<Response> syncPeer(String peerUrl) async {
    return await _dio.post('/api/peers/sync_by_url', data: {'url': peerUrl});
  }

  Future<Response> getPeerBooks(int peerId) async {
    return await _dio.get('/api/peers/$peerId/books');
  }

  Future<Response> getPeerBooksByUrl(String peerUrl) async {
    return await _dio.post('/api/peers/books_by_url', data: {'url': peerUrl});
  }

  Future<Response> requestBook(int peerId, String isbn, String title) async {
    return await _dio.post(
      '/api/peers/$peerId/request',
      data: {'book_isbn': isbn, 'book_title': title},
    );
  }

  Future<Response> requestBookByUrl(String peerUrl, String isbn, String title) async {
    return await _dio.post(
      '/api/peers/request_by_url',
      data: {'peer_url': peerUrl, 'book_isbn': isbn, 'book_title': title},
    );
  }

  Future<Response> getIncomingRequests() async {
    return await _dio.get('/api/peers/requests');
  }

  Future<Response> getOutgoingRequests() async {
    return await _dio.get('/api/peers/requests/outgoing');
  }

  Future<Response> updateRequestStatus(String requestId, String status) async {
    return await _dio.put(
      '/api/peers/requests/$requestId',
      data: {'status': status},
    );
  }

  Future<Response> deleteRequest(String requestId) async {
    return await _dio.delete('/api/peers/requests/$requestId');
  }

  Future<Response> deleteOutgoingRequest(String requestId) async {
    return await _dio.delete('/api/peers/requests/outgoing/$requestId');
  }

  // P2P Connection Requests (Hub)
  Future<Response> getPendingPeers() async {
    return await _dio.get('$hubUrl/api/peers/requests');
  }

  Future<Response> updatePeerStatus(int id, String status) async {
    return await _dio.put(
      '$hubUrl/api/peers/$id/status',
      data: {'status': status},
    );
  }

  Future<Response> deletePeer(int id) async {
    return await _dio.delete('$hubUrl/api/peers/$id');
  }

  Future<Response> updateLibraryConfig({
    required String name,
    String? description,
    List<String>? tags,
    bool? shareLocation,
    bool? showBorrowedBooks,
  }) async {
    return await _dio.post('/api/library/config', data: {
      'name': name,
      'description': description,
      'tags': tags,
      'share_location': shareLocation ?? false,
      'show_borrowed_books': showBorrowedBooks ?? false,
    });
  }

  Future<Response> setup({
    required String libraryName,
    String? libraryDescription,
    required String profileType,
    String? theme,
    double? latitude,
    double? longitude,
    bool? shareLocation,
  }) async {
    return await _dio.post('/api/setup', data: {
      'library_name': libraryName,
      'library_description': libraryDescription,
      'profile_type': profileType,
      'theme': theme,
      'latitude': latitude,
      'longitude': longitude,
      'share_location': shareLocation,
    });
  }

  Future<Response> resetApp() async {
    return await _dio.post('/api/reset');
  }

  Future<Response> searchOpenLibrary({String? title, String? author, String? subject}) async {
    final queryParams = <String, dynamic>{};
    if (title != null && title.isNotEmpty) queryParams['title'] = title;
    if (author != null && author.isNotEmpty) queryParams['author'] = author;
    if (subject != null && subject.isNotEmpty) queryParams['subject'] = subject;
    
    return await _dio.get('/api/integrations/openlibrary/search', queryParameters: queryParams);
  }

  Future<Response> updateProfile({
    required String profileType,
    Map<String, dynamic>? avatarConfig,
  }) async {
    final Map<String, dynamic> data = {
      'profile_type': profileType,
    };
    if (avatarConfig != null) {
      data['avatar_config'] = avatarConfig;
    }
    return await _dio.put('/api/profile', data: data);
  }

  Future<Map<String, dynamic>?> fetchOpenLibraryBook(String isbn) async {
    try {
      final dio = Dio(); // New instance for external call
      final response = await dio.get(
        'https://openlibrary.org/api/books',
        queryParameters: {
          'bibkeys': 'ISBN:$isbn',
          'jscmd': 'data',
          'format': 'json',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final key = 'ISBN:$isbn';
        if (data.containsKey(key)) {
          final book = data[key];
          return {
            'title': book['title'],
            'author': book['authors'] != null ? (book['authors'] as List).map((a) => a['name']).join(', ') : null,
            'publisher': book['publishers'] != null ? (book['publishers'] as List).first['name'] : null,
            'year': book['publish_date'] != null ? int.tryParse(book['publish_date'].toString().split(' ').last) : null,
            'summary': book['subtitle'] ?? (book['notes'] is String ? book['notes'] : null), // OpenLibrary structure varies
            'cover_url': book['cover'] != null ? book['cover']['large'] : null,
          };
        }
      }
    } catch (e) {
      debugPrint('OpenLibrary API Error: $e');
    }
    return null;
  }

  Future<Response> getTranslations(String locale) async {
    return await _dio.get('$hubUrl/api/translations/$locale');
  }
}
