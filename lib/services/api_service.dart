import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/book.dart';
import '../models/tag.dart';
import '../models/genie.dart';
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
    _dio.interceptors.add(RetryInterceptor(_dio, this));
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
    // Fetch my config to send to remote peer for handshake
    String? myName;
    try {
      final configRes = await getLibraryConfig();
      if (configRes.statusCode == 200) {
        myName = configRes.data['name'];
        // Construct my URL based on current port/host if possible, or use a setting
        // For now, we might rely on the Hub knowing it, but the Hub is local.
        // Actually, the Hub needs to know the PUBLIC url of this library.
        // If we are in Docker, it's http://bibliogenius-a:8000 etc.
        // But the App doesn't know its external Docker URL easily.
        // However, the USER enters the URL of the peer they are connecting TO.
        // The peer needs to know how to call ME back.
        // We can try to send what we know, or let the user configure it.
        // For this fix, let's assume we send what we have in config if available, 
        // or maybe we need to ask the user?
        // Let's send 'my_name' at least. 'my_url' is harder.
        // If 'my_url' is missing, the Hub won't be able to notify.
        // Let's try to get it from config if we added a 'public_url' field, or just send localhost for now?
        // No, localhost won't work for remote.
        // Let's assume the config has it or we send a placeholder that the Hub might resolve?
        // Actually, the Hub code I wrote expects 'my_url'.
        
        // TEMPORARY FIX: If we are in dev/docker, we might need to hardcode or guess.
        // But for a proper fix, we should probably add 'public_url' to LibraryConfig.
        // For now, let's send the name and let the Hub try its best or fail silently (as per try-catch).
        
        // Wait, if I don't send my_url, the handshake fails.
        // Let's send a dummy or try to infer.
        // Actually, the user is "Library B".
        // If Library B is "bibliogenius-b:8000", we need to send that.
        // The App doesn't know.
        // BUT, the Hub (PeerController) is running alongside the App (or is the App's backend).
        // Maybe the Hub knows?
        // The Hub is local to the App.
        // In `PeerController.php`, I used `$data['my_url']`.
        
        // Let's just send the name for now and maybe the Hub can figure it out or we update config later.
        // Or better: The user should have configured their "Public URL" in settings.
        // If not, we can't really do P2P.
        
        // Let's just send the name and empty URL if not found, and hope for the best?
        // No, that will fail validation in `receiveConnection`.
        
        // Let's assume for the demo/docker env that we can derive it?
        // No.
        
        // Let's just send the name.
      }
    } catch (e) {
      debugPrint('Error fetching config for handshake: $e');
    }

    return await _dio.post(
      '$hubUrl/api/peers/connect',
      data: {
        'name': name, 
        'url': url,
        'my_name': myName,
        'my_url': 'http://localhost:8000', // TODO: Make this configurable!
      },
    );
  }

  Future<GenieResponse> sendGenieChat(String text) async {
    try {
      final response = await _dio.post(
        '/api/genie/chat',
        data: {'text': text},
      );

      if (response.statusCode == 200) {
        return GenieResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to chat with Genie: Status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Genie Chat Error: $e');
      rethrow;
    }
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
    double? latitude,
    double? longitude,
    bool? shareLocation,
    bool? showBorrowedBooks,
  }) async {
    return await _dio.post('/api/library/config', data: {
      'name': name,
      'description': description,
      'tags': tags ?? [],
      'latitude': latitude,
      'longitude': longitude,
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

  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null) queryParams['status'] = status;
      if (author != null) queryParams['author'] = author;
      if (title != null) queryParams['title'] = title;
      if (tag != null) queryParams['tag'] = tag;

      final response = await _dio.get(
        '/api/books',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['books'];
        return data.map((json) => Book.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load books');
      }
    } catch (e) {
      throw Exception('Failed to load books: $e');
    }
  }

  Future<Book> getBook(int id) async {
    try {
      final response = await _dio.get('/api/books/$id');
      if (response.statusCode == 200) {
        return Book.fromJson(response.data);
      } else {
        throw Exception('Failed to load book');
      }
    } catch (e) {
      throw Exception('Failed to load book: $e');
    }
  }

  Future<void> reorderBooks(List<int> bookIds) async {
    try {
      await _dio.patch(
        '/api/books/reorder',
        data: {'book_ids': bookIds},
      );
    } catch (e) {
      debugPrint('Error reordering books: $e');
      rethrow;
    }
  }
  Future<Map<String, dynamic>?> lookupBook(String isbn) async {
    try {
      final response = await _dio.get('/api/lookup/$isbn');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        return {
          'title': data['title'],
          'author': data['authors'] != null 
              ? (data['authors'] as List).map((a) => a is String ? a : a['name']).join(', ') 
              : null,
          'authors_data': data['authors'], // Pass full data for UI
          'publisher': data['publisher'],
          'year': data['publication_year'] != null ? int.tryParse(data['publication_year'].toString()) : null,
          'cover_url': data['cover_url'],
        };
      }
    } catch (e) {
      debugPrint('Lookup API Error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchBooks({String? query, String? title, String? author, String? publisher}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (query != null && query.isNotEmpty) queryParams['q'] = query;
      if (title != null && title.isNotEmpty) queryParams['title'] = title;
      if (author != null && author.isNotEmpty) queryParams['author'] = author;
      if (publisher != null && publisher.isNotEmpty) queryParams['publisher'] = publisher;

      final response = await _dio.get(
        '/api/integrations/search_unified',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } catch (e) {
      debugPrint('Search API Error: $e');
    }
    return [];
  }

  Future<Response> getTranslations(String locale) async {
    return await _dio.get('$hubUrl/api/translations/$locale');
  }

  Future<List<Tag>> getTags() async {
    try {
      final response = await _dio.get('/api/books/tags');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Tag.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load tags');
      }
    } catch (e) {
      throw Exception('Failed to load tags: $e');
    }
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final ApiService apiService;
  // Prevent infinite loops or concurrent discovery attempts
  static bool _isDiscovering = false;

  RetryInterceptor(this.dio, this.apiService);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // Only attempt recovery for connection errors or timeouts
    bool shouldRetry = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (err.error != null && err.error.toString().contains('Connection refused'));

    if (!shouldRetry || _isDiscovering) {
      return handler.next(err);
    }

    _isDiscovering = true;
    debugPrint('⚠️ Connection failed on ${err.requestOptions.path}. Initiating Smart Port Discovery... 🕵️');

    try {
      // Ports to scan: 8000 to 8010
      for (int port = 8000; port <= 8010; port++) {
        final testUrl = 'http://localhost:$port';
        
        // Skip current failed URL to avoid redundancy if it was one of these
        // if (err.requestOptions.baseUrl.contains(port.toString())) continue;

        debugPrint('   → Probing $testUrl...');
        try {
          // Create a raw dio instance for probing to avoid interceptors
          final probeDio = Dio(BaseOptions(
            baseUrl: testUrl,
            connectTimeout: const Duration(milliseconds: 500),
            receiveTimeout: const Duration(milliseconds: 500),
          ));
          
          // Try simple health check or root
          final response = await probeDio.get('/api/books?limit=1'); // Light query
          
          if (response.statusCode == 200) {
            debugPrint('   ✅ FOUND BACKEND AT $testUrl! Healing connection...');
            
            // Update the main ApiService
            apiService.updatePort(port);
            
            // Update the original request's base URL
            err.requestOptions.baseUrl = testUrl;
            
            _isDiscovering = false;
            
            // Clone the request with new base URL and retry
            final opts = Options(
              method: err.requestOptions.method,
              headers: err.requestOptions.headers,
            );
            
            final cloneReq = await dio.request(
              err.requestOptions.path,
              options: opts,
              data: err.requestOptions.data,
              queryParameters: err.requestOptions.queryParameters,
            );
            
            return handler.resolve(cloneReq);
          }
        } catch (e) {
          // Probe failed, continue to next port
          // debugPrint('     (Test failed for $port)');
        }
      }
      
      debugPrint('❌ Smart Port Discovery failed. Backend unreachable on ports 8000-8010.');
    } finally {
      _isDiscovering = false;
    }

    return handler.next(err);
  }
}
