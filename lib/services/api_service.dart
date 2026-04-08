import 'dart:io' show File, SocketException;
import 'dart:ui';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:excel/excel.dart' as xlsx;

import '../models/book.dart';
import '../models/cover_candidate.dart';
import '../models/genie.dart';
import '../models/tag.dart';
import '../models/contact.dart';
import '../models/collection.dart'; // Collection module
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../src/rust/api/frb.dart' as frb;
import '../src/rust/frb_generated.dart';
import 'auth_service.dart';
import 'ffi_service.dart';
import 'mdns_service.dart';
import 'translation_service.dart';

class ApiService {
  final Dio _dio;
  final AuthService _authService;
  final bool useFfi;

  // Read from .env with fallback to localhost
  static String get defaultBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://localhost:8001';
  static String get hubUrl {
    final envUrl = dotenv.env['HUB_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    // Production builds must not default to localhost
    if (kReleaseMode) return 'https://hub.bibliogenius.org';
    return 'http://localhost:8081';
  }

  /// The actual HTTP server port (may differ from 8000 if occupied)
  static int httpPort = 8000;

  /// Track if server is known to be running
  static bool _serverKnownHealthy = false;

  /// Last time we checked server health
  static DateTime? _lastHealthCheck;

  /// Set the actual HTTP server port (called from main.dart after server starts)
  static void setHttpPort(int port) {
    httpPort = port;
    _serverKnownHealthy = true;
    _lastHealthCheck = DateTime.now();
    debugPrint('📡 ApiService: HTTP port set to $port');
  }

  /// Check if the embedded HTTP server is healthy and restart if needed.
  /// Returns true if server is available, false otherwise.
  static Future<bool> ensureServerRunning() async {
    // Quick return if recently checked and healthy
    if (_serverKnownHealthy &&
        _lastHealthCheck != null &&
        DateTime.now().difference(_lastHealthCheck!).inSeconds < 30) {
      return true;
    }

    // Try health check
    try {
      final healthDio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:$httpPort',
          connectTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      );
      final response = await healthDio.get('/api/health');
      if (response.statusCode == 200) {
        _serverKnownHealthy = true;
        _lastHealthCheck = DateTime.now();
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Server health check failed: $e');
      _serverKnownHealthy = false;
    }

    // Server not responding, try to restart
    debugPrint('🔄 Attempting to restart embedded HTTP server...');
    try {
      final newPort = await FfiService().startServer(httpPort);
      if (newPort != null) {
        httpPort = newPort;
        _serverKnownHealthy = true;
        _lastHealthCheck = DateTime.now();
        debugPrint('✅ Server restarted successfully on port $newPort');
        return true;
      }
    } catch (e) {
      debugPrint('❌ Failed to restart server: $e');
    }

    return false;
  }

  /// Mark server as unhealthy (called when connection errors occur)
  static void markServerUnhealthy() {
    _serverKnownHealthy = false;
    debugPrint('⚠️ Server marked as unhealthy');
  }

  ApiService(
    this._authService, {
    String? baseUrl,
    Dio? dio,
    this.useFfi = false,
  }) : _dio = dio ?? Dio() {
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
    // In FFI mode, login is not required (local-first mode)
    if (useFfi) {
      return Response(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        statusCode: 200,
        data: {
          'token': 'ffi_local_token',
          'message': 'Local mode - no auth needed',
        },
      );
    }
    // We expect 403 if MFA is required. Dio throws exception on 403 by default unless validated.
    // We should handle this in the UI, or wrap here.
    // Ideally we let the UI catch the error.
    return await _dio.post(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
  }

  Future<Response> loginMfa(
    String username,
    String password,
    String code,
  ) async {
    return await _dio.post(
      '/api/auth/login-mfa',
      data: {'username': username, 'password': password, 'code': code},
    );
  }

  Future<Response> setup2Fa() async {
    if (useFfi) {
      // MFA requires server connection
      throw DioException(
        requestOptions: RequestOptions(path: '/api/auth/2fa/setup'),
        message:
            'Two-factor authentication requires a server connection. Please configure a backend server.',
        type: DioExceptionType.unknown,
      );
    }
    return await _dio.post('/api/auth/2fa/setup');
  }

  Future<Response> verify2Fa(String secret, String code) async {
    if (useFfi) {
      // MFA requires server connection
      throw DioException(
        requestOptions: RequestOptions(path: '/api/auth/2fa/verify'),
        message:
            'Two-factor authentication requires a server connection. Please configure a backend server.',
        type: DioExceptionType.unknown,
      );
    }
    return await _dio.post(
      '/api/auth/2fa/verify',
      data: {'secret': secret, 'code': code},
    );
  }

  Future<Response> getMe() async {
    if (useFfi) {
      // Return mock data for FFI/Offline mode
      // Don't hardcode IDs - backend resolves dynamically when null
      return Response(
        requestOptions: RequestOptions(path: '/api/auth/me'),
        statusCode: 200,
        data: {
          'username': 'offline_user',
          'role': 'admin',
        },
      );
    }
    return await _dio.get('/api/auth/me');
  }

  Future<Response> createBook(Map<String, dynamic> bookData) async {
    if (useFfi) {
      try {
        // Native FFI Call
        // WORKAROUND: Force owned=false to prevent backend from trying to create a copy internally
        // (which fails with NotFound likely due to missing Library Context in the native struct).
        // We will manually create the copy using the working HTTP endpoint below.
        final frbBookInput = frb.FrbBook(
          title: bookData['title'] ?? 'Untitled',
          author: bookData['author'],
          isbn: bookData['isbn'],
          summary:
              bookData['description'] ?? bookData['summary'], // Handle mapping
          publisher: bookData['publisher'],
          publicationYear: bookData['publication_year'] is int
              ? bookData['publication_year']
              : int.tryParse(bookData['publication_year']?.toString() ?? ''),
          coverUrl: bookData['cover_url'],
          subjects: bookData['subjects'] != null
              ? jsonEncode(bookData['subjects'])
              : null,
          readingStatus: bookData['reading_status'],
          owned: false, // FORCE FALSE to bypass native bug
          price: bookData['price'] is num
              ? (bookData['price'] as num).toDouble()
              : null,
          private: bookData['private'] ?? false,
          pageCount: bookData['page_count'] is int
              ? bookData['page_count']
              : int.tryParse(bookData['page_count']?.toString() ?? ''),
          digitalFormats: bookData['digital_formats'] is List
              ? List<String>.from(bookData['digital_formats'])
              : null,
        );

        final createdBook = await FfiService().createBook(frbBookInput);

        // If the user wanted it owned, manually create the copy using the reliable HTTP endpoint
        if (bookData['owned'] != false) {
          if (createdBook.id == null) {
            throw Exception('Native createBook returned null ID');
          }
          await createCopy({
            'book_id': createdBook.id,
            'is_temporary': false,
            'status': 'available',
            // library_id handled by createCopy default
          });

          // [FIX] Update the book itself to owned=true so it shows up correctly in lists
          // Pass only the field we want to update; updateBook handles merging with existing data
          try {
            await updateBook(createdBook.id!, {'owned': true});
            debugPrint(
              '✅ Ownership status updated to true for Book ID ${createdBook.id}',
            );
          } catch (e) {
            debugPrint('⚠️ Failed to update ownership status: $e');
            // We don't rethrow here because the book and copy were created successfully
          }
        }

        return Response(
          requestOptions: RequestOptions(path: '/api/books'),
          statusCode: 201,
          data: {
            'id': createdBook.id,
            'title': createdBook.title,
            // Add other fields if needed by caller
          },
        );
      } catch (e) {
        debugPrint('FFI createBook error: $e');
        // Return 500 on failure to alert caller
        return Response(
          requestOptions: RequestOptions(path: '/api/books'),
          statusCode: 500,
          statusMessage: e.toString(),
        );
      }
    }
    return await _dio.post('/api/books', data: bookData);
  }

  Future<Response> updateBook(int id, Map<String, dynamic> bookData) async {
    if (useFfi) {
      try {
        // Fetch current book to preserve unchanged fields (especially required ones like title)
        final currentBook = await FfiService().getBook(id);

        final updatedFrbBook = frb.FrbBook(
          id: id,
          title: bookData['title'] ?? currentBook.title,
          author: bookData.containsKey('author')
              ? bookData['author']
              : currentBook.author,
          isbn: bookData.containsKey('isbn')
              ? bookData['isbn']
              : currentBook.isbn,
          summary: bookData.containsKey('description')
              ? bookData['description']
              : bookData.containsKey('summary')
              ? bookData['summary']
              : currentBook.summary,
          publisher: bookData.containsKey('publisher')
              ? bookData['publisher']
              : currentBook.publisher,
          publicationYear: bookData.containsKey('publication_year')
              ? (bookData['publication_year'] is int
                    ? bookData['publication_year']
                    : int.tryParse(
                        bookData['publication_year']?.toString() ?? '',
                      ))
              : currentBook.publicationYear,
          coverUrl: bookData.containsKey('cover_url')
              ? bookData['cover_url']
              : currentBook.coverUrl,
          readingStatus: bookData.containsKey('reading_status')
              ? bookData['reading_status']
              : currentBook.readingStatus,
          finishedReadingAt: bookData.containsKey('finished_reading_at')
              ? bookData['finished_reading_at']
              : currentBook.finishedReadingAt,
          startedReadingAt: bookData.containsKey('started_reading_at')
              ? bookData['started_reading_at']
              : currentBook.startedReadingAt,

          subjects: bookData.containsKey('subjects')
              ? (bookData['subjects'] != null
                    ? jsonEncode(bookData['subjects'])
                    : null)
              : (currentBook.subjects != null
                    ? jsonEncode(currentBook.subjects)
                    : null),

          largeCoverUrl: null, // Not in Book model
          shelfPosition: null, // Not in Book model
          userRating: bookData.containsKey('user_rating')
              ? bookData['user_rating']
              : currentBook.userRating,
          createdAt: null, // Not in Book model
          updatedAt: null, // Not in Book model
          owned: bookData.containsKey('owned')
              ? bookData['owned'] as bool
              : currentBook.owned,
          price: bookData.containsKey('price')
              ? (bookData['price'] is num
                    ? (bookData['price'] as num).toDouble()
                    : null)
              : currentBook.price,
          private: bookData.containsKey('private')
              ? bookData['private'] as bool
              : currentBook.private,
          pageCount: bookData.containsKey('page_count')
              ? (bookData['page_count'] is int
                    ? bookData['page_count']
                    : int.tryParse(
                        bookData['page_count']?.toString() ?? '',
                      ))
              : currentBook.pageCount,
          digitalFormats: bookData.containsKey('digital_formats')
              ? (bookData['digital_formats'] is List
                    ? List<String>.from(bookData['digital_formats'])
                    : null)
              : currentBook.digitalFormats,
        );

        final result = await FfiService().updateBook(id, updatedFrbBook);

        return Response(
          requestOptions: RequestOptions(path: '/api/books/$id'),
          statusCode: 200,
          data: {
            'id': result.id,
            'title': result.title,
            'message': 'Book updated successfully',
          },
        );
      } catch (e) {
        debugPrint('FFI updateBook error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/books/$id'),
          statusCode: 500,
          statusMessage: e.toString(),
        );
      }
    }
    return await _dio.put('/api/books/$id', data: bookData);
  }

  Future<Response> deleteBook(int id) async {
    if (useFfi) {
      try {
        await FfiService().deleteBook(id);
        return Response(
          requestOptions: RequestOptions(path: '/api/books/$id'),
          statusCode: 200,
          data: {'message': 'Book deleted successfully'},
        );
      } catch (e) {
        debugPrint('FFI deleteBook error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/books/$id'),
          statusCode: 500,
          statusMessage: e.toString(),
        );
      }
    }
    return await _dio.delete('/api/books/$id');
  }

  // Copy management - createCopy with FFI support
  Future<Response> createCopy(Map<String, dynamic> copyData) async {
    // Ensure required fields have defaults
    final enrichedData = Map<String, dynamic>.from(copyData);

    // Add library_id if not provided (get from auth service or default to 1)
    if (!enrichedData.containsKey('library_id')) {
      int? libraryId;
      try {
        libraryId = await AuthService().getLibraryId();
      } catch (e) {
        debugPrint('⚠️ Failed to get library_id from AuthService: $e');
      }

      // If AuthService didn't have it (e.g. storage cleared), try to find it from existing data
      if (libraryId == null && useFfi) {
        try {
          final contacts = await FfiService().getContacts();
          if (contacts.isNotEmpty) {
            libraryId = contacts.first.libraryOwnerId;
            debugPrint(
              '🔍 Recovered library_id $libraryId from local contacts',
            );
            // Also save it back to AuthService to fix future calls
            if (libraryId != null) {
              await AuthService().saveLibraryId(libraryId);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to recover library_id from contacts: $e');
        }
      }

      enrichedData['library_id'] = libraryId; // Backend resolves dynamically if null
    }

    // Add is_temporary if not provided (default to false)
    if (!enrichedData.containsKey('is_temporary')) {
      enrichedData['is_temporary'] = false;
    }

    Future<Response> attemptCreate(int? libId) async {
      enrichedData['library_id'] = libId;
      if (useFfi) {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.post('/api/copies', data: enrichedData);
      }
      return await _dio.post('/api/copies', data: enrichedData);
    }

    try {
      return await attemptCreate(enrichedData['library_id']);
    } catch (e) {
      // Brute force recovery failed - DB is likely uninitialized (fresh install with skipped setup)
      if (e is DioException &&
          e.response?.statusCode == 500 &&
          e.response?.data.toString().contains('FOREIGN KEY') == true) {
        debugPrint('❌ Db Uninitialized Error: Missing Default Library (ID 1).');
        debugPrint('🛠️ Attempting Self-Healing: Running Auto-Setup...');

        try {
          // Lazy Initialization: Run setup with defaults since it wasn't run at startup
          final prefs = await SharedPreferences.getInstance();
          final fallbackName = prefs.getString('libraryName') ??
              TranslationService.translateByLocale(
                  prefs.getString('languageCode') ?? 'en', 'my_library_title');
          await setup(libraryName: fallbackName, profileType: 'individual');

          // After setup, library_id should be saved in AuthService (by setup method)
          // But let's verify and retry the copy creation
          int? newLibId = await AuthService().getLibraryId();
          if (newLibId != null) {
            debugPrint(
              '✅ Auto-Setup Successful! Retrying createCopy with new Library ID: $newLibId',
            );
            return await attemptCreate(newLibId);
          }
        } catch (setupError) {
          debugPrint('❌ Auto-Setup Failed: $setupError');
        }

        throw Exception('BORROW_SETUP');
      }

      // If recovery failed or not applicable, log and rethrow original
      if (e is DioException && e.response?.data != null) {
        debugPrint('❌ createCopy error details: ${e.response?.data}');
      }
      debugPrint('❌ createCopy error: $e');
      rethrow;
    }
  }

  // Loan methods
  Future<Response> createLoan(Map<String, dynamic> loanData) async {
    if (useFfi) {
      try {
        final loanId = await RustLib.instance.api.crateApiFrbCreateLoan(
          copyId: loanData['copy_id'] as int,
          contactId: loanData['contact_id'] as int,
          libraryId: loanData['library_id'] as int? ?? 0,
          loanDate: loanData['loan_date'] as String,
          dueDate: loanData['due_date'] as String,
          notes: loanData['notes'] as String?,
        );
        return Response(
          requestOptions: RequestOptions(path: '/api/loans'),
          statusCode: 201,
          data: {
            'loan': {'id': loanId},
            'message': 'Loan created successfully',
          },
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/loans'),
          statusCode: 400,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.post('/api/loans', data: loanData);
  }

  Future<Response> getLoans({String? status, int? contactId}) async {
    if (useFfi) {
      try {
        final loans = await RustLib.instance.api.crateApiFrbGetAllLoans(
          status: status,
          contactId: contactId,
        );

        final data = loans
            .map(
              (l) => {
                'id': l.id,
                'copy_id': l.copyId,
                'contact_id': l.contactId,
                'library_id': l.libraryId,
                'loan_date': l.loanDate,
                'due_date': l.dueDate,
                'return_date': l.returnDate,
                'status': l.status,
                'notes': l.notes,
                'contact_name': l.contactName,
                'book_title': l.bookTitle,
                'book_id': l.bookId,
                'cover_url': l.coverUrl,
                'isbn': l.isbn,
              },
            )
            .toList();

        return Response(
          requestOptions: RequestOptions(path: '/api/loans'),
          statusCode: 200,
          data: {'loans': data},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/loans'),
          statusCode: 400,
          data: {'error': e.toString()},
        );
      }
    }

    Map<String, dynamic> params = {};
    if (status != null) params['status'] = status;
    if (contactId != null) params['contact_id'] = contactId;
    return await _dio.get('/api/loans', queryParameters: params);
  }

  /// Get borrowed copies (books borrowed from others, stored as temporary copies)
  Future<Response> getBorrowedCopies() async {
    // Use local HTTP server since FFI doesn't have this endpoint yet
    if (useFfi) {
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.get('/api/copies/borrowed');
    }
    return await _dio.get('/api/copies/borrowed');
  }

  Future<Response> returnLoan(int loanId) async {
    if (useFfi) {
      try {
        await RustLib.instance.api.crateApiFrbReturnLoan(id: loanId);
        return Response(
          requestOptions: RequestOptions(path: '/api/loans/$loanId/return'),
          statusCode: 200,
          data: {'message': 'Loan returned successfully'},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/loans/$loanId/return'),
          statusCode: 400,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.post('/api/loans/$loanId/return');
  }

  /// Borrower-initiated return: notifies the lender and cleans up local data.
  Future<Response> returnBorrowedBook({required int copyId}) async {
    if (useFfi) {
      final localDio =
          Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.post(
        '/api/peers/return_book',
        data: {'copy_id': copyId},
      );
    }
    return await _dio.post(
      '/api/peers/return_book',
      data: {'copy_id': copyId},
    );
  }

  // Helper to get a Dio instance for local FFI server with retry logic
  // This handles the race condition where the server might still be binding
  // and auto-restarts the server if it has crashed
  Future<Dio> _getLocalDio() async {
    // Ensure server is running before creating Dio instance
    final serverAvailable = await ensureServerRunning();
    if (!serverAvailable) {
      debugPrint('⚠️ _getLocalDio: Server not available after restart attempt');
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://127.0.0.1:$httpPort',
        connectTimeout: const Duration(milliseconds: 5000),
        receiveTimeout: const Duration(milliseconds: 5000),
      ),
    );

    // Add immediate retry for connection refused with server restart on failure
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) async {
          // Check if this is a connection error (works across all platforms)
          // Note: Error code 61 is macOS-specific, iOS uses different codes
          final isConnectionError =
              e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              (e.error is SocketException);

          if (isConnectionError) {
            // Mark server as unhealthy on connection errors
            markServerUnhealthy();

            // Check retry count
            int retries = e.requestOptions.extra['retries'] as int? ?? 0;

            // On first retry, try to restart the server
            if (retries == 0) {
              debugPrint('🔄 Connection failed, attempting server restart...');
              final restarted = await ensureServerRunning();
              if (restarted) {
                debugPrint('✅ Server restarted, retrying request...');
                // Update base URL in case port changed
                dio.options.baseUrl = 'http://127.0.0.1:$httpPort';
              }
            }

            if (retries >= 3) {
              debugPrint('❌ Local server connection failed after 3 retries.');
              return handler.next(e);
            }

            debugPrint(
              '⚠️ Local server connection error, retrying in 500ms... (Attempt ${retries + 1}/3)',
            );
            await Future.delayed(const Duration(milliseconds: 500));
            try {
              // Retry the request with the same options but incremented retry count
              final response = await dio.request(
                e.requestOptions.path,
                data: e.requestOptions.data,
                queryParameters: e.requestOptions.queryParameters,
                options: Options(
                  method: e.requestOptions.method,
                  headers: e.requestOptions.headers,
                  extra: {...e.requestOptions.extra, 'retries': retries + 1},
                ),
              );
              return handler.resolve(response);
            } catch (e2) {
              debugPrint('❌ Retry failed: $e2');
              // Pass the NEW error, not the old one
              if (e2 is DioException) {
                return handler.next(e2);
              }
              return handler.next(e);
            }
          }
          return handler.next(e);
        },
      ),
    );

    return dio;
  }

  // Collection methods
  Future<List<Collection>> getCollections() async {
    if (useFfi) {
      // Use local HTTP with retry logic
      final localDio = await _getLocalDio();
      final response = await localDio.get('/api/collections');
      final List<dynamic> data = response.data;
      return data.map((json) => Collection.fromJson(json)).toList();
    }
    final response = await _dio.get('/api/collections');
    final List<dynamic> data = response.data;
    return data.map((json) => Collection.fromJson(json)).toList();
  }

  Future<List<Collection>> getBookCollections(int bookId) async {
    final dio = useFfi ? await _getLocalDio() : _dio;
    final response = await dio.get('/api/books/$bookId/collections');
    final List<dynamic> data = response.data;
    return data.map((json) => Collection.fromJson(json)).toList();
  }

  Future<void> updateBookCollections(
    int bookId,
    List<String> collectionIds,
  ) async {
    final dio = useFfi ? await _getLocalDio() : _dio;
    await dio.put(
      '/api/books/$bookId/collections',
      data: {'collection_ids': collectionIds},
    );
  }

  Future<Collection> createCollection(
    String name, {
    String? description,
  }) async {
    final data = {'name': name, 'description': description, 'source': 'manual'};
    if (useFfi) {
      final localDio = await _getLocalDio();
      final response = await localDio.post('/api/collections', data: data);
      return Collection.fromJson(response.data);
    }
    final response = await _dio.post('/api/collections', data: data);
    return Collection.fromJson(response.data);
  }

  Future<void> deleteCollection(String id) async {
    if (useFfi) {
      final localDio = await _getLocalDio();
      await localDio.delete('/api/collections/$id');
      return;
    }
    await _dio.delete('/api/collections/$id');
  }

  Future<List<dynamic>> getCollectionBooks(String id) async {
    try {
      final dio = useFfi ? await _getLocalDio() : _dio;
      final response = await dio.get('/api/collections/$id/books');

      if (response.data is List) {
        return (response.data as List).map((e) => e).toList();
      } else if (response.data is Map && response.data['books'] is List) {
        // Handle case where it might be wrapped in { "books": [...] }
        return (response.data['books'] as List).map((e) => e).toList();
      } else {
        if (kDebugMode) {
          debugPrint(
            '⚠️ getCollectionBooks: Unexpected response format: ${response.data}',
          );
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ getCollectionBooks error: $e');
      return [];
    }
  }

  Future<void> addBookToCollection(String collectionId, int bookId) async {
    final dio = useFfi
        ? Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'))
        : _dio;
    await dio.post('/api/collections/$collectionId/books/$bookId');
  }

  Future<void> removeBookFromCollection(String collectionId, int bookId) async {
    final dio = useFfi
        ? Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'))
        : _dio;
    await dio.delete('/api/collections/$collectionId/books/$bookId');
  }

  // Copy management methods

  /// Get all copies of a specific book
  Future<Response> getBookCopies(int bookId) async {
    debugPrint('📦 getBookCopies: bookId=$bookId');
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.get('/api/books/$bookId/copies');
      } catch (e) {
        debugPrint('❌ getBookCopies error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/books/$bookId/copies'),
          statusCode: 200,
          data: {'copies': [], 'total': 0},
        );
      }
    }
    return await _dio.get('/api/books/$bookId/copies');
  }

  /// Get a single copy by ID
  Future<Response> getCopy(int copyId) async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.get('/api/copies/$copyId');
      } catch (e) {
        debugPrint('❌ getCopy error: $e');
        rethrow;
      }
    }
    return await _dio.get('/api/copies/$copyId');
  }

  /// Update a copy
  Future<Response> updateCopy(int copyId, Map<String, dynamic> data) async {
    debugPrint('📦 updateCopy: copyId=$copyId, data=$data');

    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.put('/api/copies/$copyId', data: data);
      } catch (e) {
        debugPrint('❌ updateCopy error: $e');
        rethrow;
      }
    }
    return await _dio.put('/api/copies/$copyId', data: data);
  }

  // Sales management methods (Bookseller profile)

  /// Record a new sale
  Future<Response> recordSale({
    required int copyId,
    required double salePrice,
    int? contactId,
    String? notes,
  }) async {
    final data = {
      'copy_id': copyId,
      'sale_price': salePrice,
      'contact_id': contactId,
      'notes': notes,
    };

    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.post('/api/sales', data: data);
      } catch (e) {
        debugPrint('❌ recordSale error: $e');
        rethrow;
      }
    }
    return await _dio.post('/api/sales', data: data);
  }

  /// Get all sales with optional filters
  Future<Response> getSales({
    int? limit,
    int? offset,
    String? status,
    String? search,
  }) async {
    final params = <String, dynamic>{};
    if (limit != null) params['limit'] = limit;
    if (offset != null) params['offset'] = offset;
    if (status != null) params['status'] = status;
    if (search != null) params['search'] = search;

    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.get('/api/sales', queryParameters: params);
      } catch (e) {
        debugPrint('❌ getSales error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/sales'),
          statusCode: 200,
          data: {'sales': [], 'total': 0},
        );
      }
    }
    return await _dio.get('/api/sales', queryParameters: params);
  }

  /// Cancel a sale
  Future<Response> cancelSale(int saleId) async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.delete('/api/sales/$saleId');
      } catch (e) {
        debugPrint('❌ cancelSale error: $e');
        rethrow;
      }
    }
    return await _dio.delete('/api/sales/$saleId');
  }

  /// Get sales statistics
  Future<Response> getSalesStatistics() async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.get('/api/statistics/sales');
      } catch (e) {
        debugPrint('❌ getSalesStatistics error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/statistics/sales'),
          statusCode: 200,
          data: {'sales_count': 0, 'total_revenue': 0.0, 'average_price': 0.0},
        );
      }
    }
    return await _dio.get('/api/statistics/sales');
  }

  // Contact methods
  Future<Response> getContacts({
    int? libraryId,
    String? type,
    String? bookIsbn,
  }) async {
    // When bookIsbn is provided in FFI mode, use the local HTTP server so we
    // get the has_book annotation from the backend (no FFI binding change needed).
    if (useFfi && bookIsbn == null) {
      try {
        final contacts = await FfiService().getContacts(
          libraryId: libraryId,
          type: type,
        );
        final contactsJson = contacts.map((c) => c.toJson()).toList();
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts'),
          statusCode: 200,
          data: {'contacts': contactsJson},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts'),
          statusCode: 200,
          data: {'contacts': []},
        );
      }
    }

    Map<String, dynamic> params = {};
    if (libraryId != null) params['library_id'] = libraryId;
    if (type != null) params['type'] = type;
    if (bookIsbn != null) params['book_isbn'] = bookIsbn;

    if (useFfi) {
      // bookIsbn case in FFI mode: hit the local HTTP server to get has_book.
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.get('/api/contacts', queryParameters: params);
    }
    return await _dio.get('/api/contacts', queryParameters: params);
  }

  Future<Response> getContact(int id) async {
    if (useFfi) {
      try {
        final contact = await FfiService().getContact(id);
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 200,
          data: {'contact': contact.toJson()},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 404,
          statusMessage: 'Contact not found',
        );
      }
    }
    return await _dio.get('/api/contacts/$id');
  }

  Future<Response> createContact(Map<String, dynamic> contactData) async {
    if (useFfi) {
      try {
        // Create contact via FFI
        final contact = Contact(
          type: contactData['type'] ?? 'borrower',
          name: contactData['name'] ?? '',
          firstName: contactData['first_name'],
          email: contactData['email'],
          phone: contactData['phone'],
          address: contactData['address'],
          streetAddress: contactData['street_address'],
          postalCode: contactData['postal_code'],
          city: contactData['city'],
          country: contactData['country'],
          latitude: (contactData['latitude'] as num?)?.toDouble(),
          longitude: (contactData['longitude'] as num?)?.toDouble(),
          notes: contactData['notes'],
          userId: contactData['user_id'],
          libraryOwnerId: contactData['library_owner_id'],
          isActive: contactData['is_active'] ?? true,
        );

        // Actually persist to database via FFI
        final created = await FfiService().createContact(contact);

        return Response(
          requestOptions: RequestOptions(path: '/api/contacts'),
          statusCode: 201,
          data: {
            'contact': created.toJson(),
            'message': 'Contact created successfully',
          },
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts'),
          statusCode: 500,
          statusMessage: 'Error creating contact: $e',
        );
      }
    }
    return await _dio.post('/api/contacts', data: contactData);
  }

  Future<Response> updateContact(
    int id,
    Map<String, dynamic> contactData,
  ) async {
    if (useFfi) {
      try {
        final contact = Contact(
          id: id,
          type: contactData['type'] ?? 'borrower',
          name: contactData['name'] ?? '',
          firstName: contactData['first_name'],
          email: contactData['email'],
          phone: contactData['phone'],
          address: contactData['address'],
          streetAddress: contactData['street_address'],
          postalCode: contactData['postal_code'],
          city: contactData['city'],
          country: contactData['country'],
          latitude: (contactData['latitude'] as num?)?.toDouble(),
          longitude: (contactData['longitude'] as num?)?.toDouble(),
          notes: contactData['notes'],
          userId: contactData['user_id'],
          libraryOwnerId: contactData['library_owner_id'],
          isActive: contactData['is_active'] ?? true,
        );

        final updated = await FfiService().updateContact(contact);

        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 200,
          data: {
            'contact': updated.toJson(),
            'message': 'Contact updated successfully',
          },
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 500,
          statusMessage: 'Error updating contact: $e',
        );
      }
    }
    return await _dio.put('/api/contacts/$id', data: contactData);
  }

  Future<Response> deleteContact(int id) async {
    if (useFfi) {
      try {
        await FfiService().deleteContact(id);
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 200,
          data: {'message': 'Contact deleted successfully'},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/contacts/$id'),
          statusCode: 500,
          statusMessage: 'Error deleting contact: $e',
        );
      }
    }
    return await _dio.delete('/api/contacts/$id');
  }

  Future<Response> deleteCopy(int copyId) async {
    // FFI doesn't have deleteCopy, use local HTTP server
    if (useFfi) {
      final localDio = Dio(
        BaseOptions(baseUrl: 'http://127.0.0.1:${ApiService.httpPort}'),
      );
      return await localDio.delete('/api/copies/$copyId');
    }
    return await _dio.delete('/api/copies/$copyId');
  }

  // Peer methods
  Future<Response> connectPeer(
    String name,
    String url, {
    String? libraryUuid,
    String? ed25519PublicKey,
    String? x25519PublicKey,
    String? relayUrl,
    String? mailboxId,
    String? relayWriteToken,
  }) async {
    if (useFfi) {
      return connectLocalPeer(
        name,
        url,
        libraryUuid: libraryUuid,
        ed25519PublicKey: ed25519PublicKey,
        x25519PublicKey: x25519PublicKey,
        relayUrl: relayUrl,
        mailboxId: mailboxId,
        relayWriteToken: relayWriteToken,
      );
    }
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

    // Get my local IP dynamically
    final myIp = await NetworkInfo().getWifiIP() ?? 'localhost';

    return await _dio.post(
      '$hubUrl/api/peers/connect',
      data: {
        'name': name,
        'url': url,
        'my_name': myName,
        'my_url': 'http://$myIp:$httpPort',
        if (libraryUuid != null) 'library_uuid': libraryUuid,
        if (ed25519PublicKey != null) 'ed25519_public_key': ed25519PublicKey,
        if (x25519PublicKey != null) 'x25519_public_key': x25519PublicKey,
        if (relayUrl != null) 'relay_url': relayUrl,
        if (mailboxId != null) 'mailbox_id': mailboxId,
        if (relayWriteToken != null) 'relay_write_token': relayWriteToken,
      },
    );
  }

  Future<GenieResponse> sendGenieChat(String text) async {
    try {
      final response = await _dio.post('/api/genie/chat', data: {'text': text});

      if (response.statusCode == 200) {
        return GenieResponse.fromJson(response.data);
      } else {
        throw Exception(
          'Failed to chat with Genie: Status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Genie Chat Error: $e');
      rethrow;
    }
  }

  Future<Response> getLibraryConfig() async {
    // In FFI mode, read config from the local HTTP server (single source of truth)
    // then enrich with E2EE keys from FFI and library_uuid from SharedPreferences.
    if (useFfi) {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'library_uuid': prefs.getString('library_uuid'),
      };

      // Fetch full config from local HTTP server (reads from SQLite library_config)
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
        );
        final configResp = await localDio.get('/api/config');
        if (configResp.data is Map) {
          final remote = configResp.data as Map;
          final configFallback = prefs.getString('libraryName') ??
              TranslationService.translateByLocale(
                  prefs.getString('languageCode') ?? 'en', 'my_library_title');
          data['library_name'] = remote['name'] ?? configFallback;
          data['name'] = remote['name'] ?? configFallback;
          data['description'] = remote['description'] ?? '';
          data['show_borrowed_books'] = remote['show_borrowed_books'] ?? true;
          data['share_location'] = remote['share_location'] ?? false;
          data['profile_type'] = remote['profile_type'] ?? 'individual';
          data['latitude'] = remote['latitude'];
          data['longitude'] = remote['longitude'];
          data['relay_url'] = remote['relay_url'];
          data['mailbox_id'] = remote['mailbox_id'];
          data['relay_write_token'] = remote['relay_write_token'];
          data['ed25519_public_key'] = remote['ed25519_public_key'];
          data['x25519_public_key'] = remote['x25519_public_key'];
          if (remote['library_uuid'] != null) {
            data['library_uuid'] = remote['library_uuid'];
          }
        }
      } catch (_) {
        // HTTP server not ready yet - fall back to SharedPreferences
        final prefsFallback = prefs.getString('libraryName') ??
            TranslationService.translateByLocale(
                prefs.getString('languageCode') ?? 'en', 'my_library_title');
        data['library_name'] = prefs.getString('ffi_library_name') ?? prefsFallback;
        data['name'] = prefs.getString('ffi_library_name') ?? prefsFallback;
        data['description'] = prefs.getString('ffi_library_description') ?? '';
        data['show_borrowed_books'] = prefs.getBool('ffi_show_borrowed_books') ?? true;
        data['share_location'] = prefs.getBool('ffi_share_location') ?? false;
        data['profile_type'] = prefs.getString('ffi_profile_type') ?? 'individual';
        data['latitude'] = prefs.getDouble('ffi_latitude');
        data['longitude'] = prefs.getDouble('ffi_longitude');
      }

      // Add E2EE public keys from FFI if not already present from server response
      if (data['ed25519_public_key'] == null) {
        try {
          final keysJson = await FfiService().getPublicKeys();
          if (keysJson != null) {
            final keys = jsonDecode(keysJson) as Map<String, dynamic>;
            data['ed25519_public_key'] = keys['ed25519'];
            data['x25519_public_key'] = keys['x25519'];
          }
        } catch (_) {
          // Identity not initialized yet - keys will be null
        }
      }

      return Response(
        requestOptions: RequestOptions(path: '/api/config'),
        statusCode: 200,
        data: data,
      );
    }
    return await _dio.get('/api/config');
  }

  // Gamification
  Future<Response> getUserStatus() async {
    // In FFI mode, delegate to Rust via FFI (single source of truth)
    if (useFfi) {
      try {
        final status = await FfiService().getGamificationStatus();
        return Response(
          requestOptions: RequestOptions(path: '/api/user/status'),
          statusCode: 200,
          data: _frbStatusToJson(status),
        );
      } catch (e) {
        debugPrint('FFI getUserStatus error: $e');
        // Fallback to defaults on error
        return Response(
          requestOptions: RequestOptions(path: '/api/user/status'),
          statusCode: 200,
          data: {
            'tracks': {
              'collector': {'level': 0, 'progress': 0.0, 'current': 0, 'next_threshold': 25},
              'reader': {'level': 0, 'progress': 0.0, 'current': 0, 'next_threshold': 25},
              'lender': {'level': 0, 'progress': 0.0, 'current': 0, 'next_threshold': 25},
              'cataloguer': {'level': 0, 'progress': 0.0, 'current': 0, 'next_threshold': 25},
            },
            'streak': {'current': 0, 'longest': 0},
            'recent_achievements': <String>[],
            'config': {
              'achievements_style': 'minimal',
              'reading_goal_yearly': 12,
              'reading_goal_progress': 0,
              'total_books_read': 0,
            },
            'level': 'Member',
            'loans_count': 0,
            'edits_count': 0,
            'next_level_progress': 0.0,
            'badge_url': '',
          },
        );
      }
    }
    return await _dio.get('/api/user/status');
  }

  /// Get network gamification leaderboard
  Future<Response> getLeaderboard() async {
    if (useFfi) {
      try {
        final lb = await FfiService().getGamificationLeaderboard();
        return Response(
          requestOptions: RequestOptions(path: '/api/gamification/leaderboard'),
          statusCode: 200,
          data: _frbLeaderboardToJson(lb),
        );
      } catch (e) {
        if (!e.toString().contains('gamification is disabled')) {
          debugPrint('FFI getLeaderboard error: $e');
        }
      }
    }
    try {
      return await _dio.get('/api/gamification/leaderboard');
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('gamification is disabled') &&
          !msg.contains("Unsupported scheme 'ffi'")) {
        debugPrint('Leaderboard: server unavailable, returning empty ($e)');
      }
      return Response(
        requestOptions: RequestOptions(path: '/api/gamification/leaderboard'),
        statusCode: 200,
        data: {'collector': [], 'reader': [], 'lender': [], 'cataloguer': []},
      );
    }
  }

  /// Refresh leaderboard by syncing gamification stats from all connected peers,
  /// then return the updated leaderboard data.
  /// Note: peer sync requires the HTTP endpoint, so this still uses HTTP.
  /// Uses a longer timeout because the backend polls peers in parallel (up to 5s each).
  Future<Response> refreshLeaderboard() async {
    try {
      final dio = useFfi ? await _getLocalDio() : _dio;
      return await dio.post(
        '/api/gamification/refresh-leaderboard',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
    } catch (e) {
      if (e is! DioException || e.response?.statusCode != 403) {
        debugPrint('Refresh leaderboard failed, falling back to cached ($e)');
      }
      return getLeaderboard();
    }
  }

  /// Update gamification config (reading goals, etc.)
  Future<Response> updateGamificationConfig({
    int? readingGoalYearly,
    int? readingGoalMonthly,
    String? achievementsStyle,
    Map<String, dynamic>? fallbackPreferences,
  }) async {
    if (useFfi) {
      await FfiService().updateGamificationConfig(
        readingGoalYearly: readingGoalYearly,
        achievementsStyle: achievementsStyle,
      );
      return Response(
        requestOptions: RequestOptions(path: '/api/user/config'),
        statusCode: 200,
        data: {'message': 'Config updated successfully'},
      );
    }
    final data = <String, dynamic>{};
    if (readingGoalYearly != null) {
      data['reading_goal_yearly'] = readingGoalYearly;
    }
    if (readingGoalMonthly != null) {
      data['reading_goal_monthly'] = readingGoalMonthly;
    }
    if (achievementsStyle != null) {
      data['achievements_style'] = achievementsStyle;
    }
    if (fallbackPreferences != null) {
      data['fallback_preferences'] = fallbackPreferences;
    }
    return await _dio.put('/api/user/config', data: data);
  }

  // ============ FFI → JSON conversion helpers ============

  /// Convert FrbGamificationStatus to JSON map matching GamificationStatus.fromJson
  Map<String, dynamic> _frbStatusToJson(frb.FrbGamificationStatus status) {
    Map<String, dynamic> trackToJson(frb.FrbTrackProgress t) => {
      'level': t.level,
      'progress': t.progress,
      'current': t.current.toInt(),
      'next_threshold': t.nextThreshold,
    };
    return {
      'tracks': {
        'collector': trackToJson(status.collector),
        'reader': trackToJson(status.reader),
        'lender': trackToJson(status.lender),
        'cataloguer': trackToJson(status.cataloguer),
      },
      'streak': {
        'current': status.streak.current,
        'longest': status.streak.longest,
      },
      'recent_achievements': status.recentAchievements,
      'config': {
        'achievements_style': status.config.achievementsStyle,
        'reading_goal_yearly': status.config.readingGoalYearly,
        'reading_goal_progress': status.config.readingGoalProgress,
        'total_books_read': status.config.totalBooksRead,
      },
      'level': status.level,
      'loans_count': status.loansCount.toInt(),
      'edits_count': status.editsCount.toInt(),
      'next_level_progress': status.nextLevelProgress,
      'badge_url': status.badgeUrl,
    };
  }

  /// Convert FrbLeaderboardResponse to JSON map matching leaderboard consumers
  Map<String, dynamic> _frbLeaderboardToJson(frb.FrbLeaderboardResponse lb) {
    List<Map<String, dynamic>> entriesToJson(List<frb.FrbLeaderboardEntry> entries) =>
        entries.map((e) => {
          'library_name': e.libraryName,
          'level': e.level,
          'current': e.current.toInt(),
          'is_self': e.isSelf,
          'peer_id': e.peerId,
        }).toList();
    return {
      'collector': entriesToJson(lb.collector),
      'reader': entriesToJson(lb.reader),
      'lender': entriesToJson(lb.lender),
      'cataloguer': entriesToJson(lb.cataloguer),
      if (lb.lastRefreshed != null) 'last_refreshed': lb.lastRefreshed,
    };
  }

  // Export
  Future<Response> exportData() async {
    if (useFfi) {
      // Delegate to local HTTP server for complete backup with all entities
      try {
        final localDio = await _getLocalDio();
        return await localDio.get(
          '/api/export',
          options: Options(responseType: ResponseType.bytes),
        );
      } catch (e) {
        debugPrint('FFI export error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/export'),
          statusCode: 500,
          statusMessage: 'Export failed: $e',
        );
      }
    }

    return await _dio.get(
      '/api/export',
      options: Options(responseType: ResponseType.bytes),
    );
  }

  /// Import a JSON backup file to restore library data
  Future<Response> importBackup(List<int> jsonBytes) async {
    // Parse the JSON to send as structured data
    try {
      final jsonString = utf8.decode(jsonBytes);
      final jsonData = jsonDecode(jsonString);

      if (useFfi) {
        // In FFI mode, POST to local HTTP server
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
        );
        return await localDio.post('/api/import', data: jsonData);
      }

      return await _dio.post('/api/import', data: jsonData);
    } catch (e) {
      debugPrint('Import backup error: $e');
      return Response(
        requestOptions: RequestOptions(path: '/api/import'),
        statusCode: 500,
        data: {'error': 'Failed to parse backup file: $e'},
      );
    }
  }

  /// Push local backup data to a linked peer via upsert.
  /// [peerBaseUrl] is the full base URL of the peer (e.g. "http://192.168.1.42:8000").
  Future<bool> pushBackupToPeer(String peerBaseUrl) async {
    try {
      // 1. Export local data
      final localDio = await _getLocalDio();
      final exportResp = await localDio.get('/api/export');
      if (exportResp.statusCode != 200 || exportResp.data == null) {
        debugPrint('Auto-backup: export failed (status=${exportResp.statusCode})');
        return false;
      }

      // 2. Push to peer's upsert endpoint
      final peerDio = Dio(
        BaseOptions(
          baseUrl: peerBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final importResp = await peerDio.post(
        '/api/import-upsert',
        data: exportResp.data,
      );
      debugPrint(
        'Auto-backup: pushed to $peerBaseUrl -> ${importResp.data?['message'] ?? importResp.statusCode}',
      );
      return importResp.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Auto-backup: push to $peerBaseUrl failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Auto-backup: push to $peerBaseUrl failed: $e');
      return false;
    }
  }

  Future<Response> importBooks(dynamic fileSource, {String? filename}) async {
    // FFI mode: Parse CSV/XLSX and create books locally
    if (useFfi) {
      try {
        // Check if file is XLSX based on filename or content
        final isXlsx =
            filename?.toLowerCase().endsWith('.xlsx') == true ||
            (fileSource is List<int> && _isXlsxBytes(fileSource));

        if (isXlsx) {
          return await _importFromXlsx(fileSource, filename);
        }

        String csvContent;
        if (fileSource is String) {
          // Native: Check if path ends with .xlsx
          if (fileSource.toLowerCase().endsWith('.xlsx')) {
            return await _importFromXlsx(fileSource, filename);
          }
          // Native: Read file from path
          final file = File(fileSource);
          csvContent = await file.readAsString();
        } else if (fileSource is List<int>) {
          // Web: Convert bytes to string
          csvContent = utf8.decode(fileSource);
        } else {
          throw Exception("Unsupported file source type");
        }

        // Parse CSV
        final lines = csvContent
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          return Response(
            requestOptions: RequestOptions(path: '/api/import'),
            statusCode: 400,
            data: {'error': 'Empty file'},
          );
        }

        // First line is header
        final header = _parseCsvLine(lines.first);
        final headerLower = header.map((h) => h.toLowerCase().trim()).toList();

        // Find column indices - support multiple formats including Goodreads
        final titleIdx = headerLower.indexWhere(
          (h) => h.contains('title') || h.contains('titre'),
        );
        final authorIdx = headerLower.indexWhere(
          (h) => h.contains('author') || h.contains('auteur'),
        );
        // Goodreads uses "ISBN13" column - prefer it over regular ISBN if both exist
        int isbnIdx = headerLower.indexWhere(
          (h) => h == 'isbn13' || h == 'isbn 13',
        );
        if (isbnIdx == -1) {
          isbnIdx = headerLower.indexWhere((h) => h.contains('isbn'));
        }
        final publisherIdx = headerLower.indexWhere(
          (h) =>
              h.contains('publisher') ||
              h.contains('editeur') ||
              h.contains('éditeur'),
        );
        // Goodreads uses "Year Published" or "Original Publication Year"
        int yearIdx = headerLower.indexWhere(
          (h) => h == 'year published' || h == 'original publication year',
        );
        if (yearIdx == -1) {
          yearIdx = headerLower.indexWhere(
            (h) =>
                h.contains('year') ||
                h.contains('année') ||
                h.contains('annee'),
          );
        }

        if (titleIdx == -1) {
          return Response(
            requestOptions: RequestOptions(path: '/api/import'),
            statusCode: 400,
            data: {
              'error':
                  'Title column not found. Make sure CSV has a "Title" header.',
            },
          );
        }

        int imported = 0;
        for (int i = 1; i < lines.length; i++) {
          final values = _parseCsvLine(lines[i]);
          if (values.isEmpty ||
              (titleIdx < values.length && values[titleIdx].trim().isEmpty)) {
            continue;
          }

          try {
            // Helper to get value or null if empty
            String? getValueOrNull(int idx) {
              if (idx < 0 || idx >= values.length) return null;
              var val = values[idx].trim();
              // Handle Goodreads-style ="VALUE" format (prevents Excel number conversion)
              if (val.startsWith('="') && val.endsWith('"')) {
                val = val.substring(2, val.length - 1);
              }
              return val.isEmpty ? null : val;
            }

            final book = frb.FrbBook(
              title: titleIdx < values.length
                  ? values[titleIdx].trim()
                  : 'Unknown',
              author: getValueOrNull(authorIdx),
              isbn: getValueOrNull(isbnIdx),
              publisher: getValueOrNull(publisherIdx),
              publicationYear: yearIdx >= 0 && yearIdx < values.length
                  ? int.tryParse(values[yearIdx].trim())
                  : null,
              owned: true,
              private: false,
            );
            await FfiService().createBook(book);
            imported++;
          } catch (e) {
            debugPrint('Error importing book at line $i: $e');
            // Continue with next book
          }
        }

        return Response(
          requestOptions: RequestOptions(path: '/api/import'),
          statusCode: 200,
          data: {'imported': imported, 'message': 'Import successful'},
        );
      } catch (e) {
        debugPrint('FFI import error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/import'),
          statusCode: 500,
          data: {'error': 'Import failed: $e'},
        );
      }
    }

    // HTTP mode
    MultipartFile file;
    if (fileSource is String) {
      final name = filename ?? fileSource.split('/').last;
      file = await MultipartFile.fromFile(fileSource, filename: name);
    } else if (fileSource is List<int>) {
      file = MultipartFile.fromBytes(
        fileSource,
        filename: filename ?? 'import.csv',
      );
    } else {
      throw Exception("Unsupported file source type");
    }

    FormData formData = FormData.fromMap({"file": file});
    return await _dio.post('/api/import/file', data: formData);
  }

  /// Parse a CSV line handling quoted fields
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  /// Check if bytes represent an XLSX file (ZIP with PK signature)
  bool _isXlsxBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // XLSX files are ZIP files, which start with PK (0x50, 0x4B)
    return bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  /// Import books from an XLSX file (supports Gleeph export format)
  Future<Response> _importFromXlsx(dynamic fileSource, String? filename) async {
    try {
      List<int> bytes;
      if (fileSource is String) {
        // File path
        final file = File(fileSource);
        bytes = await file.readAsBytes();
      } else if (fileSource is List<int>) {
        bytes = fileSource;
      } else {
        throw Exception("Unsupported file source type for XLSX");
      }

      final excel = xlsx.Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.rows.isEmpty) {
        return Response(
          requestOptions: RequestOptions(path: '/api/import'),
          statusCode: 400,
          data: {'error': 'Empty XLSX file or no sheets found'},
        );
      }

      // Get headers from first row
      final headerRow = sheet.rows.first;
      final headers = headerRow
          .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
          .toList();

      // Find column indices - support Gleeph format
      final titleIdx = headers.indexWhere(
        (h) => h == 'book_title' || h.contains('title') || h.contains('titre'),
      );
      final isbnIdx = headers.indexWhere((h) => h.contains('isbn'));
      final wishIdx = headers.indexWhere((h) => h == 'wish');
      final ownIdx = headers.indexWhere((h) => h == 'own');
      final readingIdx = headers.indexWhere((h) => h == 'reading');
      final readIdx = headers.indexWhere((h) => h == 'read');
      final shelvesIdx = headers.indexWhere((h) => h == 'shelves');
      // Note: favorite column is parsed but not yet used

      if (titleIdx == -1) {
        return Response(
          requestOptions: RequestOptions(path: '/api/import'),
          statusCode: 400,
          data: {
            'error':
                'Title column not found. Expected "book_title" or "Title" column.',
          },
        );
      }

      // Collect unique shelf names from all rows
      final Set<String> uniqueShelves = {};
      if (shelvesIdx >= 0) {
        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || shelvesIdx >= row.length) continue;
          final cell = row[shelvesIdx];
          if (cell?.value != null) {
            final cellValue = cell!.value;
            String shelfName;
            if (cellValue is xlsx.TextCellValue) {
              shelfName = cellValue.value.text ?? '';
            } else {
              shelfName = cellValue.toString();
            }
            shelfName = shelfName.trim();
            if (shelfName.isNotEmpty && shelfName != 'null') {
              uniqueShelves.add(shelfName);
            }
          }
        }
      }

      // Get existing shelves and create missing ones
      final Set<String> existingShelfNames = {};
      int shelvesCreated = 0;
      if (uniqueShelves.isNotEmpty) {
        try {
          final existingTags = await FfiService().getTags();
          for (final tag in existingTags) {
            existingShelfNames.add(tag.name.toLowerCase());
          }

          // Create shelves that don't exist
          for (final shelfName in uniqueShelves) {
            if (!existingShelfNames.contains(shelfName.toLowerCase())) {
              try {
                await FfiService().createTag(shelfName);
                existingShelfNames.add(shelfName.toLowerCase());
                shelvesCreated++;
                debugPrint('Created shelf: $shelfName');
              } catch (e) {
                debugPrint('Error creating shelf "$shelfName": $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching/creating shelves: $e');
        }
      }

      int imported = 0;
      int skipped = 0;

      // Process data rows (skip header)
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        try {
          // Get cell value safely - handles xlsx CellValue types
          String? getCellValue(int idx) {
            if (idx < 0 || idx >= row.length) return null;
            final cell = row[idx];
            if (cell == null || cell.value == null) return null;
            final cellValue = cell.value;
            String value;
            // Handle different CellValue types from excel package
            if (cellValue is xlsx.TextCellValue) {
              value = cellValue.value.text ?? '';
            } else if (cellValue is xlsx.IntCellValue) {
              value = cellValue.value.toString();
            } else if (cellValue is xlsx.DoubleCellValue) {
              value = cellValue.value.toString();
            } else if (cellValue is xlsx.BoolCellValue) {
              value = cellValue.value.toString();
            } else {
              value = cellValue.toString();
            }
            value = value.trim();
            if (value.isEmpty || value == 'null') return null;
            return value;
          }

          // Get boolean value from cell
          bool getBoolValue(int idx) {
            if (idx < 0 || idx >= row.length) return false;
            final cell = row[idx];
            if (cell == null || cell.value == null) return false;
            final cellValue = cell.value;
            if (cellValue is xlsx.BoolCellValue) return cellValue.value;
            if (cellValue is xlsx.IntCellValue) return cellValue.value == 1;
            if (cellValue is xlsx.DoubleCellValue)
              return cellValue.value == 1.0;
            final strValue = cellValue.toString().toLowerCase().trim();
            // Support English and French boolean values
            return strValue == 'true' ||
                strValue == 'vrai' ||
                strValue == '1' ||
                strValue == 'yes' ||
                strValue == 'oui';
          }

          final title = getCellValue(titleIdx);
          if (title == null || title.isEmpty) {
            skipped++;
            continue;
          }

          // Parse ISBN - may be in scientific notation (e.g., 9.782253140191E12)
          String? isbn = getCellValue(isbnIdx);
          if (isbn != null && isbn.isNotEmpty) {
            var isbnValue = isbn;
            // Handle scientific notation (e.g., 9.782253140191E12)
            if (isbnValue.contains('E') || isbnValue.contains('e')) {
              try {
                final numValue = double.parse(isbnValue);
                isbnValue = numValue.toStringAsFixed(0);
              } catch (_) {
                // Keep original value if parsing fails
              }
            }
            // Handle decimal format (e.g., 9782253140191.0 → 9782253140191)
            if (isbnValue.contains('.')) {
              try {
                final numValue = double.parse(isbnValue);
                isbnValue = numValue.toStringAsFixed(0);
              } catch (_) {
                // Remove decimal part manually
                isbnValue = isbnValue.split('.').first;
              }
            }
            // Remove any non-digit characters except X (for ISBN-10)
            isbnValue = isbnValue.replaceAll(RegExp(r'[^\dXx]'), '');
            isbn = isbnValue.isEmpty ? null : isbnValue;
          }

          // Determine reading status based on Gleeph flags
          // Priority: wish (wanting) > read > reading > to_read
          String readingStatus;
          final isWish = getBoolValue(wishIdx);
          final isOwn = getBoolValue(ownIdx);
          final isReading = getBoolValue(readingIdx);
          final isRead = getBoolValue(readIdx);

          if (isWish) {
            // Wishlist: book is wanted but not necessarily owned
            readingStatus = 'wanting';
          } else if (isRead) {
            readingStatus = 'read';
          } else if (isReading) {
            readingStatus = 'reading';
          } else {
            readingStatus = 'to_read';
          }

          // Determine if owned:
          // Gleeph export has own=false for ALL books (export bug/limitation)
          // So we deduce ownership from context:
          // - wish=true → wishlist item → not owned
          // - wish=false → book in library → owned (default assumption)
          // - If own column is explicitly true, respect it
          final owned = isOwn || (!isWish);

          // Get shelf name for this book
          String? shelfName;
          if (shelvesIdx >= 0 && shelvesIdx < row.length) {
            final shelfCell = row[shelvesIdx];
            if (shelfCell?.value != null) {
              final cellValue = shelfCell!.value;
              if (cellValue is xlsx.TextCellValue) {
                shelfName = cellValue.value.text ?? '';
              } else {
                shelfName = cellValue.toString();
              }
              shelfName = shelfName.trim();
              if (shelfName.isEmpty || shelfName == 'null') {
                shelfName = null;
              }
            }
          }

          // Create the book with shelf as subject
          final book = frb.FrbBook(
            title: title,
            isbn: isbn,
            readingStatus: readingStatus,
            owned: owned,
            subjects: shelfName != null ? jsonEncode([shelfName]) : null,
            private: false,
          );

          await FfiService().createBook(book);
          imported++;
        } catch (e) {
          debugPrint('Error importing row $i: $e');
          skipped++;
        }
      }

      return Response(
        requestOptions: RequestOptions(path: '/api/import'),
        statusCode: 200,
        data: {
          'imported': imported,
          'skipped': skipped,
          'shelves_created': shelvesCreated,
          'message': shelvesCreated > 0
              ? 'XLSX import successful ($shelvesCreated shelves created)'
              : 'XLSX import successful',
        },
      );
    } catch (e) {
      debugPrint('XLSX import error: $e');
      return Response(
        requestOptions: RequestOptions(path: '/api/import'),
        statusCode: 500,
        data: {'error': 'XLSX import failed: $e'},
      );
    }
  }

  // P2P Advanced
  Future<Response> getPeers() async {
    if (useFfi) {
      // Call local HTTP API to get peers
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final response = await localDio.get('/api/peers');
        debugPrint('✅ getPeers: ${(response.data as Map)['data']?.length ?? 0} peers');
        return response;
      } catch (e) {
        // Expected timeout in FFI mode (no local HTTP server)
        return Response(
          requestOptions: RequestOptions(path: '/api/peers'),
          statusCode: 500,
          data: {'error': e.toString(), 'data': []},
        );
      }
    } // End if (useFfi)
    return await _dio.get('$hubUrl/api/peers');
  }

  Future<Response> importCollectionBooks(
    String collectionId,
    dynamic fileSource, {
    String? filename,
    bool importAsOwned = false,
  }) async {
    final dio = useFfi
        ? Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'))
        : _dio;

    MultipartFile file;
    if (fileSource is String) {
      final name = filename ?? fileSource.split('/').last;
      file = await MultipartFile.fromFile(fileSource, filename: name);
    } else if (fileSource is List<int>) {
      file = MultipartFile.fromBytes(
        fileSource,
        filename: filename ?? 'import.csv',
      );
    } else {
      throw Exception("Unsupported file source type");
    }

    FormData formData = FormData.fromMap({"file": file});
    return await dio.post(
      '/api/collections/$collectionId/books',
      data: formData,
      queryParameters: {'owned': importAsOwned},
    );
  }

  Future<Response> searchPeers(String query) async {
    if (useFfi) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/search'),
        statusCode: 200,
        data: [],
      );
    }
    return await _dio.get(
      '$hubUrl/api/peers/search',
      queryParameters: {'q': query},
    );
  }

  /// Update a peer's URL (for mDNS IP changes)
  Future<Response> updatePeerUrl(int peerId, String newUrl, {String? libraryUuid}) async {
    final body = <String, dynamic>{'url': newUrl};
    if (libraryUuid != null) {
      body['library_uuid'] = libraryUuid;
    }
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
          ),
        );
        return await localDio.put(
          '/api/peers/$peerId/url',
          data: body,
        );
      } catch (e) {
        debugPrint('❌ updatePeerUrl error: $e');
        rethrow;
      }
    }
    return await _dio.put('/api/peers/$peerId/url', data: body);
  }

  Future<Response> syncPeer(String peerUrl, {bool skipLan = false}) async {
    // relay:// URLs are relay-only peers - skip direct HTTP sync
    if (peerUrl.startsWith('relay://')) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
        statusCode: 200,
        data: {'message': 'Relay-only peer, skipping direct sync'},
      );
    }

    // Ensure URL has http:// prefix
    final normalizedUrl = peerUrl.startsWith('http')
        ? peerUrl
        : 'http://$peerUrl';

    if (useFfi) {
      // FFI mode: Direct P2P sync (bidirectional)
      try {
        // When mDNS is disabled, skip LAN attempt (stale URL, 30s timeout).
        // Go directly to local backend which handles relay fallback.
        if (skipLan) {
          if (kDebugMode) debugPrint('P2P Sync: LAN skipped (mDNS off), relay via backend for $normalizedUrl');
          final localDio = Dio(
            BaseOptions(
              baseUrl: 'http://127.0.0.1:${ApiService.httpPort}',
              connectTimeout: const Duration(seconds: 5),
              // Backend may spend up to ~110s total: config fetch (5s) +
              // direct E2EE attempt (10s) + relay await (90s) + overhead.
              // Consistent with relayLibraryRequest timeout.
              receiveTimeout: const Duration(seconds: 110),
            ),
          );
          final res = await localDio.post(
            '/api/peers/sync_by_url',
            data: {'url': normalizedUrl},
          );
          return res;
        }

        final myUrl = await _getMyUrl();
        if (myUrl == null) {
          return Response(
            requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
            statusCode: 503,
            data: {'error': 'No valid LAN IP available for P2P sync'},
          );
        }

        // 1. Ask remote peer to sync from us (non-blocking for step 2)
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        debugPrint(
          'P2P Sync: Requesting sync from $normalizedUrl/api/peers/sync_by_url with my URL $myUrl',
        );
        Response? remoteRes;
        bool remoteOk = false;
        try {
          remoteRes = await dio.post(
            '$normalizedUrl/api/peers/sync_by_url',
            data: {'url': myUrl},
          );
          remoteOk = true;
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            // 404 means the remote doesn't recognize our URL (peer reset,
            // different WiFi, URL mismatch). This is NOT a disconnect signal.
            // Don't return early - fall through to local backend sync which
            // handles relay fallback for peers unreachable via LAN.
            debugPrint(
              'P2P Sync: Remote returned 404 for $normalizedUrl '
              '(keeping peer, falling through to local sync/relay)',
            );
          }
          debugPrint('P2P remote sync error (non-fatal): $e');
        } catch (e) {
          debugPrint('P2P remote sync error (non-fatal): $e');
        }

        // 2. Sync locally from the remote peer via local backend (handles E2EE)
        bool localOk = false;
        try {
          final localDio = Dio(
            BaseOptions(
              baseUrl: 'http://127.0.0.1:${ApiService.httpPort}',
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          await localDio.post(
            '/api/peers/sync_by_url',
            data: {'url': normalizedUrl},
          );
          localOk = true;
        } catch (e) {
          debugPrint('P2P local sync error (non-fatal): $e');
        }

        // If BOTH steps failed, throw so SyncService backoff kicks in
        if (!remoteOk && !localOk) {
          throw Exception('Both remote and local sync failed for $normalizedUrl');
        }

        return remoteRes ?? Response(
          requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
          statusCode: 200,
          data: {'message': 'Local sync completed'},
        );
      } catch (e) {
        debugPrint('P2P Sync Error: $e');
        // Rethrow so SyncService backoff can catch it
        rethrow;
      }
    }
    return await _dio.post('/api/peers/sync_by_url', data: {'url': peerUrl});
  }

  Future<Response> getPeerBooks(int peerId) async {
    if (useFfi) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/$peerId/books'),
        statusCode: 200,
        data: [],
      );
    }
    return await _dio.get('/api/peers/$peerId/books');
  }

  Future<Response> getPeerBooksByUrl(String peerUrl) async {
    // Route through local Rust backend which handles E2EE encryption
    // and plaintext fallback internally.
    if (useFfi) {
      try {
        final dio = Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:$httpPort',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 15),
        ));
        debugPrint('📡 Fetching peer books via local backend for $peerUrl');
        final response = await dio.post(
          '/api/peers/proxy_search',
          data: {'peer_url': peerUrl, 'query': ''},
        );
        debugPrint('📡 Peer books result: ${response.data?.length ?? 0} books');
        return response;
      } catch (e) {
        debugPrint('📡 Peer books via backend failed: $e');
        rethrow;
      }
    }
    // HTTP mode: direct P2P call
    try {
      final cleanUrl = peerUrl.endsWith('/')
          ? peerUrl.substring(0, peerUrl.length - 1)
          : peerUrl;
      final targetUrl = '$cleanUrl/api/books?owned_only=true';
      debugPrint('P2P: Fetching books from $targetUrl');
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      return await dio.get(targetUrl);
    } catch (e) {
      debugPrint('P2P: Error fetching books from $peerUrl - $e');
      rethrow;
    }
  }

  /// Fetch a single page of a peer's library with pagination.
  /// Returns { "books": [...], "total": N, "has_more": bool } when the remote
  /// peer supports pagination, or a flat array (legacy) for older peers.
  Future<Response> getPeerBooksPage(
    String peerUrl, {
    int page = 0,
    int limit = 20,
  }) async {
    if (useFfi) {
      try {
        final dio = Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:$httpPort',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 15),
        ));
        final response = await dio.post(
          '/api/peers/proxy_search',
          data: {
            'peer_url': peerUrl,
            'query': '',
            'page': page,
            'limit': limit,
          },
        );
        return response;
      } catch (e) {
        debugPrint('Paginated peer books via backend failed: $e');
        rethrow;
      }
    }
    // HTTP mode: direct P2P call with pagination
    try {
      final cleanUrl = peerUrl.endsWith('/')
          ? peerUrl.substring(0, peerUrl.length - 1)
          : peerUrl;
      final targetUrl =
          '$cleanUrl/api/books?owned_only=true&page=$page&limit=$limit';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      return await dio.get(targetUrl);
    } catch (e) {
      debugPrint('P2P paginated: Error fetching books from $peerUrl - $e');
      rethrow;
    }
  }

  /// Get cached peer books with staleness metadata from local backend
  /// This does NOT contact the peer directly - it reads from local cache
  /// Returns: { books, peer_name, peer_id, last_synced, last_seen, cached }
  Future<Response> getCachedPeerBooks(String peerUrl) async {
    try {
      final localDio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:$httpPort',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return await localDio.post(
        '/api/peers/cached_books_by_url',
        data: {'url': peerUrl},
      );
    } catch (e) {
      debugPrint('Error fetching cached peer books: $e');
      rethrow;
    }
  }

  /// Save pre-fetched books to local peer_books cache.
  /// Called after relay or live WiFi fetch to avoid redundant re-fetches.
  Future<void> cachePeerBooks(int peerId, List<Book> books) async {
    try {
      final localDio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:$httpPort',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      await localDio.post(
        '/api/peers/$peerId/cache_books',
        data: {'books': books.map((b) => b.toJson()).toList()},
      );
    } catch (e) {
      debugPrint('Error caching peer books: $e');
      rethrow;
    }
  }

  /// Cleanup peer_books cache entries older than 30 days (privacy TTL)
  /// Call this on app startup to auto-purge stale caches
  Future<void> cleanupStalePeerBooksCache() async {
    try {
      final localDio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:$httpPort',
          connectTimeout: const Duration(seconds: 10),
        ),
      );
      final response = await localDio.post('/api/peers/cleanup_stale_cache');
      int deletedCount = 0;
      if (response.data is Map) {
        deletedCount = response.data['deleted'] ?? 0;
      }
      if (deletedCount > 0 && kDebugMode) {
        debugPrint(
          '🧹 TTL cleanup: removed $deletedCount stale peer book cache entries',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Peer cache cleanup failed: $e');
      // Silent failure - cleanup is not critical
    }
  }

  // ============ Cover Enrichment ============

  /// Enrich books that have an ISBN but no cover by checking external sources.
  /// Returns the number of covers found and persisted.
  Future<int> enrichMissingCovers() async {
    if (useFfi) {
      return await FfiService().enrichMissingCovers();
    }
    return 0;
  }

  /// Search for a cover URL for a single ISBN from external sources.
  Future<String?> searchCoverForBook(String isbn) async {
    if (useFfi) {
      return await FfiService().searchCoverForBook(isbn);
    }
    return null;
  }

  /// Search for a cover URL by title with author verification (fallback).
  Future<String?> searchCoverByTitle(String title, String? author, {bool enableGoogle = false}) async {
    if (useFfi) {
      return await FfiService().searchCoverByTitle(title, author, enableGoogle: enableGoogle);
    }
    return null;
  }

  /// Search all cover sources in parallel for a given ISBN.
  /// Returns all cover candidates for the picker carousel.
  Future<List<CoverCandidate>> searchAllCoversForBook(String isbn) async {
    if (useFfi) {
      return await FfiService().searchAllCoversForBook(isbn);
    }
    return [];
  }

  /// Search all cover sources by title in parallel.
  Future<List<CoverCandidate>> searchAllCoversByTitle(
      String title, String? author,
      {bool enableGoogle = false}) async {
    if (useFfi) {
      return await FfiService()
          .searchAllCoversByTitle(title, author, enableGoogle: enableGoogle);
    }
    return [];
  }

  /// Look up book metadata from external sources by ISBN.
  /// Returns a map of field names to values, or null if not found.
  Future<Map<String, String?>?> lookupBookMetadata(String isbn, {String? lang}) async {
    if (useFfi) {
      return await FfiService().lookupBookMetadata(isbn, lang: lang);
    }
    return null;
  }

  Future<Response> requestBook(int peerId, String isbn, String title) async {
    if (useFfi) {
      return Response(
        requestOptions: RequestOptions(path: '/api/peers/request'),
        statusCode: 200,
        data: {'message': 'Request not available in offline mode'},
      );
    }
    return await _dio.post(
      '/api/peers/request',
      data: {'peer_id': peerId, 'book_isbn': isbn, 'book_title': title},
    );
  }

  Future<Response> requestBookByUrl(
    String peerUrl,
    String isbn,
    String title,
  ) async {
    // Route through local Rust backend which handles E2EE encryption,
    // outgoing request tracking, and plaintext fallback internally.
    final dio = useFfi
        ? Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'))
        : _dio;
    debugPrint('📡 Sending loan request via local backend for peer $peerUrl');
    final response = await dio.post(
      '/api/peers/request_by_url',
      data: {'peer_url': peerUrl, 'book_isbn': isbn, 'book_title': title},
    );
    final msg = response.data is Map ? response.data['message'] : '';
    debugPrint('📡 Loan request result: $msg');
    return response;
  }

  Future<Response> getIncomingRequests() async {
    if (useFfi) {
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.get('/api/peers/requests');
    }
    return await _dio.get('/api/peers/requests');
  }

  Future<Response> getOutgoingRequests() async {
    if (useFfi) {
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.get('/api/peers/requests/outgoing');
    }
    return await _dio.get('/api/peers/requests/outgoing');
  }

  /// Sync pending outgoing requests by querying lenders for current status.
  /// Returns { synced: N, updated: N }.
  Future<Response> syncOutgoingRequests() async {
    if (useFfi) {
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.post('/api/peers/requests/outgoing/sync');
    }
    return await _dio.post('/api/peers/requests/outgoing/sync');
  }

  Future<Response> updateRequestStatus(String requestId, String status) async {
    debugPrint(
      '📝 updateRequestStatus: id=$requestId, status=$status, useFfi=$useFfi',
    );
    if (useFfi) {
      // In FFI mode, call the local HTTP server directly
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        final res = await localDio.put(
          '/api/peers/requests/$requestId',
          data: {'status': status},
        );
        debugPrint('✅ updateRequestStatus response: ${res.statusCode}');
        return res;
      } catch (e) {
        debugPrint('❌ updateRequestStatus error: $e');
        rethrow;
      }
    }
    return await _dio.put(
      '/api/peers/requests/$requestId',
      data: {'status': status},
    );
  }

  Future<Response> deleteRequest(String requestId) async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.delete('/api/peers/requests/$requestId');
      } catch (e) {
        debugPrint('❌ deleteRequest error: $e');
        rethrow;
      }
    }
    return await _dio.delete('/api/peers/requests/$requestId');
  }

  Future<Response> deleteOutgoingRequest(String requestId) async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        return await localDio.delete('/api/peers/requests/outgoing/$requestId');
      } catch (e) {
        debugPrint('❌ deleteOutgoingRequest error: $e');
        rethrow;
      }
    }
    return await _dio.delete('/api/peers/requests/outgoing/$requestId');
  }

  Future<Response> clearOutgoingRequests() async {
    final localDio = await _getLocalDio();
    return await localDio.delete('/api/peers/requests/outgoing/clear');
  }

  Future<Response> clearIncomingRequests() async {
    final localDio = await _getLocalDio();
    return await localDio.delete('/api/peers/requests/clear');
  }

  // P2P Connection Requests (Hub)
  Future<Response> getPendingPeers() async {
    if (useFfi) {
      // In FFI mode, call the local HTTP API to get peers
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final response = await localDio.get('/api/peers');
        if (response.statusCode == 200) {
          // Handle both formats: {data: [...]} or direct [...]
          List allPeers;
          if (response.data is Map && response.data['data'] != null) {
            allPeers = response.data['data'] as List;
          } else if (response.data is List) {
            allPeers = response.data as List;
          } else {
            allPeers = [];
          }

          // Filter for peers with pending connection status
          final pendingPeers = allPeers
              .where((p) => p['connection_status'] == 'pending')
              .map((p) {
                final Map<String, dynamic> peer = Map<String, dynamic>.from(
                  p as Map,
                );
                peer['direction'] = 'incoming'; // Mark as incoming for UI
                return peer;
              })
              .toList();
          debugPrint(
            '📋 getPendingPeers: Found ${pendingPeers.length} pending from ${allPeers.length} total',
          );
          for (var p in pendingPeers) {
            debugPrint(
              '  📚 Peer: id=${p['id']}, name="${p['name']}", url=${p['url']}, auto_approve=${p['auto_approve']}',
            );
          }
          return Response(
            requestOptions: RequestOptions(path: '/api/peers'),
            statusCode: 200,
            data: {'requests': pendingPeers},
          );
        }
      } catch (e) {
        debugPrint('❌ getPendingPeers HTTP error: $e');
      }
      // Fallback to empty
      return Response(
        requestOptions: RequestOptions(path: '$hubUrl/api/peers/requests'),
        statusCode: 200,
        data: {'requests': []},
      );
    }
    return await _dio.get('$hubUrl/api/peers/requests');
  }

  Future<Response> updatePeerStatus(int id, String status) async {
    if (useFfi) {
      // Call local HTTP API to update peer status
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final response = await localDio.put(
          '/api/peers/$id/status',
          data: {'status': status},
        );
        debugPrint('✅ updatePeerStatus: $status for peer $id');
        return response;
      } catch (e) {
        debugPrint('❌ updatePeerStatus error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/peers/$id/status'),
          statusCode: 500,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.put(
      '$hubUrl/api/peers/$id/status',
      data: {'status': status},
    );
  }

  Future<Response> deletePeer(int id) async {
    if (useFfi) {
      // Call local HTTP API to delete peer
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final response = await localDio.delete('/api/peers/$id');
        debugPrint('🗑️ deletePeer: peer $id deleted');
        return response;
      } catch (e) {
        debugPrint('❌ deletePeer error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/peers/$id'),
          statusCode: 500,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.delete('$hubUrl/api/peers/$id');
  }

  /// Update a peer's user-defined display name.
  Future<Response> updatePeerDisplayName(int peerId, String name) async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        return await localDio.patch(
          '/api/peers/$peerId/display-name',
          data: {'display_name': name},
        );
      } catch (e) {
        debugPrint('updatePeerDisplayName error: $e');
        return Response(
          requestOptions:
              RequestOptions(path: '/api/peers/$peerId/display-name'),
          statusCode: 500,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.patch(
      '/api/peers/$peerId/display-name',
      data: {'display_name': name},
    );
  }

  /// Bulk-approve all pending peers (called when connection validation is disabled)
  Future<Response> autoApproveAllPeers() async {
    if (useFfi) {
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://localhost:${ApiService.httpPort}',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final response = await localDio.post('/api/peers/auto_approve_all');
        debugPrint('✅ autoApproveAllPeers: ${response.data}');
        return response;
      } catch (e) {
        debugPrint('❌ autoApproveAllPeers error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/peers/auto_approve_all'),
          statusCode: 500,
          data: {'error': e.toString()},
        );
      }
    }
    return await _dio.post('$hubUrl/api/peers/auto_approve_all');
  }

  /// Check if a peer is reachable by performing a quick health check
  /// Returns true if the peer responds within the timeout, false otherwise
  /// Returns true if the peer responds within the timeout, false otherwise
  Future<bool> checkPeerConnectivity(String url, {int timeoutMs = 3000}) async {
    // relay:// URLs are relay-only peers - no direct HTTP connectivity
    if (url.startsWith('relay://')) return false;
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: Duration(milliseconds: timeoutMs),
          receiveTimeout: Duration(milliseconds: timeoutMs),
          validateStatus: (status) {
            // Consider 401/403 as "Online" (reachable but auth required)
            // Consider 200-299 as success
            return status != null && (status < 500);
          },
        ),
      );
      // Try a public endpoint or root. /api/books requires auth, but if we get 401/403, it means it's ALIVE.
      await dio.get('$url/api/books?limit=1');
      return true; // If no exception (due to validateStatus), it's reachable
    } catch (e) {
      // Expected when peer is offline — not a warning
      debugPrint('Peer unreachable: $url');
      return false;
    }
  }

  /// Fetch a remote peer's /api/config to retrieve its library_uuid.
  /// Returns the library_uuid if reachable, null otherwise.
  Future<String?> fetchPeerLibraryUuid(String peerUrl, {int timeoutMs = 2000}) async {
    if (peerUrl.startsWith('relay://')) return null;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: Duration(milliseconds: timeoutMs),
        receiveTimeout: Duration(milliseconds: timeoutMs),
      ));
      final resp = await dio.get('$peerUrl/api/config');
      if (resp.statusCode == 200 && resp.data is Map) {
        return resp.data['library_uuid'] as String?;
      }
    } catch (e) {
      debugPrint('fetchPeerLibraryUuid failed for $peerUrl: $e');
    }
    return null;
  }

  // ============================================
  // Relay Library Sync (ADR-012)
  // ============================================

  /// Trigger an immediate relay poll cycle to check for pending responses.
  /// Used in adaptive polling when awaiting relay responses.
  Future<Response> pollRelayNow() async {
    try {
      final localDio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:$httpPort',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return await localDio.post('/api/relay/poll_now');
    } catch (e) {
      debugPrint('pollRelayNow error: $e');
      rethrow;
    }
  }

  /// Send a library sync request to a peer via relay (ADR-012).
  /// Diagnostic: log local relay configuration and mailbox status.
  Future<void> logRelayStatus() async {
    try {
      final localDio = Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:$httpPort',
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final resp = await localDio.get('/api/relay/status');
      debugPrint('Relay status (local): ${resp.data}');
    } catch (e) {
      debugPrint('Relay status check failed: $e');
    }
  }

  /// Returns the response directly if peer is on LAN, or { status: "relay_pending" }
  /// if sent via relay (response arrives asynchronously).
  ///
  /// [requestType]: "manifest", "page", or "search"
  Future<Response> relayLibraryRequest({
    required int peerId,
    required String requestType,
    int? cursor,
    int? limit,
    String? query,
  }) async {
    try {
      // Relay requests may block up to ~100s on the Rust side:
      // 10s direct transport timeout + 90s relay await with polling
      // (90s covers one full remote poller cycle of 60s + 10s jitter + margin).
      // Use 110s receiveTimeout to accommodate this plus network overhead.
      final localDio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:$httpPort',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 110),
        ),
      );
      final data = <String, dynamic>{
        'peer_id': peerId,
        'request_type': requestType,
      };
      if (cursor != null) data['cursor'] = cursor;
      if (limit != null) data['limit'] = limit;
      if (query != null) data['query'] = query;

      if (kDebugMode) debugPrint('relayLibraryRequest: peer=$peerId type=$requestType cursor=$cursor');
      final response = await localDio.post(
        '/api/peers/relay/library_request',
        data: data,
      );
      if (kDebugMode) {
        debugPrint(
          'relayLibraryRequest: peer=$peerId type=$requestType '
          'status=${response.statusCode}',
        );
      }
      return response;
    } catch (e) {
      if (e is DioException) {
        if (kDebugMode) {
          debugPrint(
            'relayLibraryRequest error: peer=$peerId type=$requestType '
            'HTTP ${e.response?.statusCode} '
            'dioType=${e.type}',
          );
        }
      } else {
        if (kDebugMode) debugPrint('relayLibraryRequest error: peer=$peerId type=$requestType $e');
      }
      rethrow;
    }
  }

  /// Request peer library manifest (book count + catalog hash).
  /// If LAN: returns immediately. If relay: starts async flow.
  /// Returns `{'error': 'peer_unreachable'}` on 502 so the caller can
  /// stop retrying without needing Dio imports. Returns null on 202
  /// (relay_pending).
  Future<Map<String, dynamic>?> requestPeerManifest(int peerId) async {
    try {
      final response = await relayLibraryRequest(
        peerId: peerId,
        requestType: 'manifest',
      );
      if (response.statusCode == 200) {
        return response.data is Map<String, dynamic>
            ? response.data
            : null;
      }
      // 202 = relay_pending, response will come via polling
      if (kDebugMode) debugPrint('requestPeerManifest: peer=$peerId status=${response.statusCode}');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 502) {
        // Peer unreachable (mailbox expired, credential refresh failed).
        // Return sentinel map so the caller can break out of retry loops.
        debugPrint(
          'requestPeerManifest: peer=$peerId 502 peer_unreachable - ${e.response?.data}',
        );
        return {'error': 'peer_unreachable'};
      }
      debugPrint(
        'requestPeerManifest error: peer=$peerId HTTP ${e.response?.statusCode} - ${e.response?.data}',
      );
      return null;
    } catch (e) {
      debugPrint('requestPeerManifest error: peer=$peerId $e');
      return null;
    }
  }

  /// Request a page of peer's library (paginated, 50 books/page).
  Future<Map<String, dynamic>?> requestPeerPage(
    int peerId, {
    int? cursor,
    int limit = 50,
  }) async {
    try {
      final response = await relayLibraryRequest(
        peerId: peerId,
        requestType: 'page',
        cursor: cursor,
        limit: limit,
      );
      if (response.statusCode == 200) {
        return response.data is Map<String, dynamic>
            ? response.data
            : null;
      }
      if (kDebugMode) debugPrint('requestPeerPage: peer=$peerId cursor=$cursor status=${response.statusCode}');
      return null;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'requestPeerPage error: peer=$peerId cursor=$cursor '
          'HTTP ${e.response?.statusCode}',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('requestPeerPage error: peer=$peerId cursor=$cursor $e');
      return null;
    }
  }

  /// Search a peer's library remotely (relay or direct).
  Future<Map<String, dynamic>?> searchPeerLibrary(
    int peerId,
    String query, {
    int limit = 20,
  }) async {
    try {
      final response = await relayLibraryRequest(
        peerId: peerId,
        requestType: 'search',
        query: query,
        limit: limit,
      );
      if (response.statusCode == 200) {
        return response.data is Map<String, dynamic>
            ? response.data
            : null;
      }
      return null;
    } catch (e) {
      debugPrint('searchPeerLibrary error: $e');
      return null;
    }
  }

  // ============================================
  // mDNS Local Discovery
  // ============================================

  /// Get libraries discovered on the local network via mDNS
  Future<Response> getLocalPeers() async {
    // Use native MdnsService for local discovery (works on iOS/macOS via Bonjour)
    final peers = MdnsService.getPeersJson();
    final isActive = MdnsService.isActive;
    debugPrint(
      '🔍 ApiService: getLocalPeers() returning ${peers.length} peers',
    );
    return Response(
      requestOptions: RequestOptions(path: '/api/discovery/local'),
      statusCode: 200,
      data: {'peers': peers, 'count': peers.length, 'mdns_active': isActive},
    );
  }

  /// Get mDNS service status (active/inactive)
  Future<Response> getMdnsStatus() async {
    final isActive = MdnsService.isActive;
    return Response(
      requestOptions: RequestOptions(path: '/api/discovery/status'),
      statusCode: 200,
      data: {'active': isActive, 'service_type': '_bibliogenius._tcp'},
    );
  }

  /// Helper to get my own URL (IP address) for P2P handshake.
  /// Uses multiple strategies to find a valid LAN IP, never falls back to
  /// 127.0.0.1 which would be useless for remote peers and cause UNIQUE
  /// constraint conflicts in the peers table.
  Future<String?> _getMyUrl() async {
    String? myIp;
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && !wifiIp.startsWith('169.254.')) {
        myIp = wifiIp;
      }
    } catch (e) {
      debugPrint('Failed to get WiFi IP: $e');
    }
    // Fallback: enumerate network interfaces (works for wired connections)
    myIp ??= await MdnsService.getValidLanIp();
    if (myIp == null) {
      debugPrint('⚠️ P2P: No valid LAN IP found, cannot build peer URL');
      return null;
    }
    return 'http://$myIp:${ApiService.httpPort}';
  }

  /// Send a pairing code to a remote peer's HTTP server.
  /// The peer must have generated the code first.
  Future<Map<String, dynamic>> sendPairingCode({
    required String peerUrl,
    required String code,
    required String deviceName,
    required List<int> ed25519PublicKey,
    required List<int> x25519PublicKey,
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: peerUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    final response = await dio.post('/api/devices/pair/accept', data: {
      'code': code,
      'device_name': deviceName,
      'ed25519_public_key': ed25519PublicKey,
      'x25519_public_key': x25519PublicKey,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Connect to a locally discovered peer by URL.
  /// Optional E2EE keys from QR/invite/mDNS are forwarded to the Rust backend.
  Future<Response> connectLocalPeer(
    String name,
    String url, {
    String? libraryUuid,
    String? ed25519PublicKey,
    String? x25519PublicKey,
    String? relayUrl,
    String? mailboxId,
    String? relayWriteToken,
  }) async {
    debugPrint(
      'P2P connectLocalPeer: name="$name" url="$url" '
      'libraryUuid=$libraryUuid e2ee=${ed25519PublicKey != null} '
      'relay=${relayUrl != null} mailbox=$mailboxId',
    );

    if (useFfi) {
      try {
        // 1. Get my own details (SharedPreferences is the source of truth for library name)
        final prefs = await SharedPreferences.getInstance();
        String myName = prefs.getString('libraryName') ??
            TranslationService.translateByLocale(
                prefs.getString('languageCode') ?? 'en', 'my_library_title');
        final myUrl = await _getMyUrl();
        final peerHasLanUrl = url.isNotEmpty && !url.startsWith('relay://');
        final hasRelayCredentials = relayUrl != null && mailboxId != null;

        // Relay-only path: either we have no LAN IP, or the peer has no LAN URL
        // (per ADR-004: relay fallback when direct LAN is unavailable)
        if ((myUrl == null || !peerHasLanUrl) && hasRelayCredentials) {
          if (kDebugMode) {
            debugPrint(
              'P2P: relay-only connection (myUrl=${myUrl != null}, peerUrl=$peerHasLanUrl)',
            );
          }
          try {
            final localDio = Dio(BaseOptions(
              baseUrl: 'http://localhost:${ApiService.httpPort}',
            ));
            if (kDebugMode) debugPrint('P2P relay-only: saving peer locally');
            // Send empty URL — Rust generates a unique relay:// placeholder
            final saveResponse = await localDio.post(
              '/api/peers/connect',
              data: {
                'name': name,
                'url': '',
                if (libraryUuid != null) 'library_uuid': libraryUuid,
                if (ed25519PublicKey != null)
                  'ed25519_public_key': ed25519PublicKey,
                if (x25519PublicKey != null)
                  'x25519_public_key': x25519PublicKey,
                'relay_url': relayUrl,
                'mailbox_id': mailboxId,
                if (relayWriteToken != null)
                  'relay_write_token': relayWriteToken,
              },
            );
            if (kDebugMode) debugPrint('P2P relay-only: peer saved HTTP ${saveResponse.statusCode}');

            // Deposit connection_request in remote peer's relay mailbox
            // via Dio (native HTTP stack). Rust's reqwest+rustls fails
            // on iOS FFI, so Flutter handles the hub deposit directly.
            final wt = relayWriteToken;
            if (wt != null) {
              try {
                await _depositConnectionRequest(
                  localDio: localDio,
                  peerRelayUrl: relayUrl,
                  peerMailboxId: mailboxId,
                  peerWriteToken: wt,
                );
              } on DioException catch (depositErr) {
                if (depositErr.response?.statusCode == 404) {
                  debugPrint(
                    'P2P relay-only: deposit 404 -- peer mailbox stale, '
                    'removing ghost peer',
                  );
                  final peerId = saveResponse.data is Map
                      ? saveResponse.data['id']
                      : null;
                  if (peerId != null) {
                    try {
                      await localDio.delete('/api/peers/$peerId');
                    } catch (_) {}
                  }
                  return Response(
                    requestOptions:
                        RequestOptions(path: '/api/peers/connect'),
                    statusCode: 404,
                    data: {
                      'error': 'peer_relay_mailbox_expired',
                    },
                  );
                }
              }
            }

            return saveResponse;
          } catch (e) {
            return Response(
              requestOptions: RequestOptions(path: '/api/peers/connect'),
              statusCode: 502,
              data: {'error': 'Failed to save peer via relay path: $e'},
            );
          }
        }

        if (myUrl == null && !hasRelayCredentials) {
          // No LAN AND no relay info - genuinely cannot connect
          return Response(
            requestOptions: RequestOptions(path: '/api/peers/connect'),
            statusCode: 503,
            data: {'error': 'No valid LAN IP available for P2P handshake'},
          );
        }

        // 2. Send handshake request to Peer
        final targetUrl = '$url/api/peers/incoming';
        debugPrint(
          'P2P Handshake: Sending my info ($myName, $myUrl) to $targetUrl',
        );

        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        // Get our own public keys and relay info to send in the handshake
        Map<String, dynamic>? myKeys;
        try {
          final localDioForKeys = Dio(
            BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
          );
          final configResp = await localDioForKeys.get('/api/config');
          if (configResp.data is Map) {
            myKeys = {
              if (configResp.data['library_uuid'] != null)
                'library_uuid': configResp.data['library_uuid'],
              if (configResp.data['ed25519_public_key'] != null)
                'ed25519_public_key': configResp.data['ed25519_public_key'],
              if (configResp.data['x25519_public_key'] != null)
                'x25519_public_key': configResp.data['x25519_public_key'],
              if (configResp.data['relay_url'] != null)
                'relay_url': configResp.data['relay_url'],
              if (configResp.data['mailbox_id'] != null)
                'mailbox_id': configResp.data['mailbox_id'],
              if (configResp.data['relay_write_token'] != null)
                'relay_write_token': configResp.data['relay_write_token'],
            };
          }
        } catch (e) {
          debugPrint('Could not load own E2EE keys for handshake: $e');
        }

        final response = await dio.post(
          targetUrl,
          data: {
            'name': myName,
            'url': myUrl,
            if (myKeys != null) ...myKeys,
          },
        );

        debugPrint(
          'P2P Handshake Success: ${response.statusCode} - ${response.data}',
        );

        // Extract the remote peer's keys and relay info from the handshake response
        // Prefer handshake response values, fall back to invite payload values
        String? remoteEd25519 = ed25519PublicKey;
        String? remoteX25519 = x25519PublicKey;
        String? remoteRelayUrl = relayUrl;
        String? remoteMailboxId = mailboxId;
        String? remoteRelayWriteToken = relayWriteToken;
        if (response.data is Map) {
          remoteEd25519 ??= response.data['ed25519_public_key'] as String?;
          remoteX25519 ??= response.data['x25519_public_key'] as String?;
          remoteRelayUrl ??= response.data['relay_url'] as String?;
          remoteMailboxId ??= response.data['mailbox_id'] as String?;
          remoteRelayWriteToken ??=
              response.data['relay_write_token'] as String?;
        }

        // 3. Save peer locally (FFI mode) with E2EE keys and relay info
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
        );
        // Extract remote library_uuid from handshake response if available
        String? remoteLibraryUuid = libraryUuid;
        if (response.data is Map) {
          remoteLibraryUuid ??= response.data['library_uuid'] as String?;
        }

        final saveResponse = await localDio.post(
          '/api/peers/connect',
          data: {
            'name': name,
            'url': url,
            if (remoteLibraryUuid != null) 'library_uuid': remoteLibraryUuid,
            if (remoteEd25519 != null) 'ed25519_public_key': remoteEd25519,
            if (remoteX25519 != null) 'x25519_public_key': remoteX25519,
            if (remoteRelayUrl != null) 'relay_url': remoteRelayUrl,
            if (remoteMailboxId != null) 'mailbox_id': remoteMailboxId,
            if (remoteRelayWriteToken != null)
              'relay_write_token': remoteRelayWriteToken,
          },
        );
        debugPrint('Peer saved locally: $name (status=${saveResponse.statusCode})');

        return response;
      } on DioException catch (e) {
        debugPrint(
          'P2P Connect DioException: type=${e.type} status=${e.response?.statusCode} '
          'message=${e.message}',
        );

        // LAN handshake failed (different network, peer offline, etc.).
        // If relay credentials are available, fall back to relay-only path
        // so the remote peer still gets our connection_request.
        if (relayUrl != null && mailboxId != null) {
          debugPrint(
            'P2P Connect: LAN failed (${e.type}), falling back to relay-only '
            '(mailbox=$mailboxId)',
          );
          try {
            final localDio = Dio(BaseOptions(
              baseUrl: 'http://localhost:${ApiService.httpPort}',
            ));
            final saveResponse = await localDio.post(
              '/api/peers/connect',
              data: {
                'name': name,
                'url': url,
                if (libraryUuid != null) 'library_uuid': libraryUuid,
                if (ed25519PublicKey != null)
                  'ed25519_public_key': ed25519PublicKey,
                if (x25519PublicKey != null)
                  'x25519_public_key': x25519PublicKey,
                'relay_url': relayUrl,
                'mailbox_id': mailboxId,
                if (relayWriteToken != null)
                  'relay_write_token': relayWriteToken,
              },
            );
            debugPrint(
              'P2P relay fallback: peer saved HTTP ${saveResponse.statusCode}',
            );

            final wt = relayWriteToken;
            if (wt != null) {
              try {
                await _depositConnectionRequest(
                  localDio: localDio,
                  peerRelayUrl: relayUrl,
                  peerMailboxId: mailboxId,
                  peerWriteToken: wt,
                );
              } on DioException catch (depositErr) {
                if (depositErr.response?.statusCode == 404) {
                  debugPrint(
                    'P2P relay fallback: deposit 404 -- peer mailbox '
                    'stale, removing ghost peer',
                  );
                  final peerId = saveResponse.data is Map
                      ? saveResponse.data['id']
                      : null;
                  if (peerId != null) {
                    try {
                      await localDio.delete('/api/peers/$peerId');
                    } catch (_) {}
                  }
                  return Response(
                    requestOptions:
                        RequestOptions(path: '/api/peers/connect'),
                    statusCode: 404,
                    data: {
                      'error': 'peer_relay_mailbox_expired',
                    },
                  );
                }
              }
            }

            return saveResponse;
          } catch (relayErr) {
            debugPrint('P2P relay fallback failed: $relayErr');
          }
        }

        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;

        String errorDetail;
        if (responseData != null) {
          errorDetail = responseData is Map
              ? (responseData['error']?.toString() ?? responseData.toString())
              : responseData.toString();
        } else {
          switch (e.type) {
            case DioExceptionType.connectionTimeout:
              errorDetail = 'Connection timed out - peer may be offline';
            case DioExceptionType.receiveTimeout:
              errorDetail = 'Peer did not respond in time';
            case DioExceptionType.connectionError:
              errorDetail = 'Could not reach peer - check network and URL';
            case DioExceptionType.badResponse:
              errorDetail = 'Peer responded with error (${statusCode ?? "unknown"})';
            default:
              errorDetail = e.message ?? e.type.toString();
          }
        }

        return Response(
          requestOptions: e.requestOptions,
          statusCode: statusCode ?? 502,
          data: {
            'error': errorDetail,
            'status': statusCode,
          },
        );
      } catch (e) {
        debugPrint('P2P Connect Error: $e');
        return Response(
          requestOptions: RequestOptions(path: '/api/peers/connect'),
          statusCode: 500,
          data: {'error': e.toString()},
        );
      }
    }
    // Use the existing peer connect mechanism
    return await _dio.post(
      '/api/peers/connect',
      data: {'name': name, 'url': url},
    );
  }

  /// Deposit a connection_request in a remote peer's relay mailbox.
  ///
  /// Called from Flutter (Dio) instead of Rust (reqwest) because reqwest+rustls
  /// fails on iOS FFI. Dio uses the native HTTP stack which works everywhere.
  ///
  /// Ensures our own relay is configured before depositing, so the remote
  /// peer receives our relay credentials and can reach us back.
  Future<void> _depositConnectionRequest({
    required Dio localDio,
    required String peerRelayUrl,
    required String peerMailboxId,
    required String peerWriteToken,
  }) async {
    try {
      // 1. Load our own config (name, E2EE keys, relay credentials)
      var configResp = await localDio.get('/api/config');
      if (configResp.statusCode != 200 || configResp.data is! Map) {
        debugPrint('Relay deposit: could not load local config');
        return;
      }
      var config = configResp.data as Map<String, dynamic>;

      // 2. Ensure our relay is configured before depositing. Without our
      //    relay credentials in the payload the remote peer cannot reach us.
      //    Relay auto-setup runs in main() but may not have completed yet.
      if (config['relay_url'] == null || config['mailbox_id'] == null) {
        if (kDebugMode) debugPrint('Relay deposit: local relay not configured, auto-setup');
        try {
          await localDio.post(
            '/api/peers/relay/setup',
            data: {'relay_url': ApiService.hubUrl},
          );
          configResp = await localDio.get('/api/config');
          if (configResp.statusCode == 200 && configResp.data is Map) {
            config = configResp.data as Map<String, dynamic>;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Relay deposit: relay auto-setup failed: $e');
        }
      }

      // 3. Build the connection_request payload (same format as Rust)
      final payload = <String, dynamic>{
        'type': 'connection_request',
        'name': config['library_name'] ?? 'BiblioGenius User',
        'url': '', // No reliable URL without LAN
      };
      if (config['library_uuid'] != null) {
        payload['library_uuid'] = config['library_uuid'];
      }
      if (config['ed25519_public_key'] != null) {
        payload['ed25519_public_key'] = config['ed25519_public_key'];
      }
      if (config['x25519_public_key'] != null) {
        payload['x25519_public_key'] = config['x25519_public_key'];
      }
      // Include our relay credentials so remote peer can write back to us
      if (config['relay_url'] != null) {
        payload['relay_url'] = config['relay_url'];
      }
      if (config['mailbox_id'] != null) {
        payload['mailbox_id'] = config['mailbox_id'];
      }
      if (config['relay_write_token'] != null) {
        payload['relay_write_token'] = config['relay_write_token'];
      }

      final hasRelayCreds = payload.containsKey('relay_url')
          && payload.containsKey('mailbox_id');
      if (!hasRelayCreds && kDebugMode) {
        debugPrint(
          'Relay deposit: WARNING local relay credentials missing, '
          'peer will not be able to reach us via relay',
        );
      }

      // 4. Deposit in remote peer's mailbox via hub
      final depositUrl =
          '${peerRelayUrl.replaceAll(RegExp(r'/+$'), '')}/api/relay/mailbox/$peerMailboxId/messages';
      if (kDebugMode) {
        debugPrint(
          'Relay deposit: POST '
          '(e2ee=${payload.containsKey('ed25519_public_key')}, '
          'relay_creds=$hasRelayCreds)',
        );
      }

      final hubDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final blob = utf8.encode(jsonEncode(payload));
      final resp = await hubDio.post<dynamic>(
        depositUrl,
        data: Stream.fromIterable([blob]),
        options: Options(
          headers: {
            'Authorization': 'Bearer $peerWriteToken',
            'Content-Type': 'application/octet-stream',
            'Content-Length': blob.length,
          },
          responseType: ResponseType.json,
        ),
      );
      if (kDebugMode) {
        debugPrint('Relay deposit: ${resp.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 404 = mailbox no longer exists on the hub (definitive error).
        // Rethrow so the caller can inform the user.
        if (kDebugMode) {
          debugPrint('Relay deposit: 404 mailbox not found (stale credentials)');
        }
        rethrow;
      }
      // Transient errors (timeout, 500, network) -- log and swallow.
      if (kDebugMode) debugPrint('Relay deposit failed (transient): $e');
    } catch (e) {
      if (kDebugMode) debugPrint('Relay deposit failed: $e');
    }
  }

  Future<Response> updateLibraryConfig({
    required String name,
    String? description,
    String? profileType,
    List<String>? tags,
    double? latitude,
    double? longitude,
    bool? shareLocation,
    bool? showBorrowedBooks,
  }) async {
    // In FFI mode, persist config to SharedPreferences AND to the Rust DB
    if (useFfi) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ffi_library_name', name);
      if (description != null)
        await prefs.setString('ffi_library_description', description);
      if (profileType != null)
        await prefs.setString('ffi_profile_type', profileType);
      if (tags != null) await prefs.setStringList('ffi_tags', tags);
      if (latitude != null) await prefs.setDouble('ffi_latitude', latitude);
      if (longitude != null) await prefs.setDouble('ffi_longitude', longitude);
      if (shareLocation != null)
        await prefs.setBool('ffi_share_location', shareLocation);
      if (showBorrowedBooks != null)
        await prefs.setBool('ffi_show_borrowed_books', showBorrowedBooks);

      // Also persist to the Rust backend DB so leaderboard/config stay in sync
      try {
        final localDio = await _getLocalDio();
        await localDio.post('/api/library/config', data: {
          'name': name,
          'description': description,
          'profile_type': profileType,
          'tags': tags ?? [],
          'latitude': latitude,
          'longitude': longitude,
          'share_location': shareLocation ?? false,
          'show_borrowed_books': showBorrowedBooks ?? false,
        });
      } catch (e) {
        debugPrint('FFI config sync to DB failed: $e');
      }

      return Response(
        requestOptions: RequestOptions(path: '/api/library/config'),
        statusCode: 200,
        data: {
          'name': name,
          'description': description,
          'tags': tags ?? [],
          'latitude': latitude,
          'longitude': longitude,
          'share_location': shareLocation ?? false,
          'show_borrowed_books': showBorrowedBooks ?? false,
          'message': 'Configuration saved locally',
        },
      );
    }
    return await _dio.post(
      '/api/library/config',
      data: {
        'name': name,
        'description': description,
        'profile_type': profileType,
        'tags': tags ?? [],
        'latitude': latitude,
        'longitude': longitude,
        'share_location': shareLocation ?? false,
        'show_borrowed_books': showBorrowedBooks ?? false,
      },
    );
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
    // In FFI mode, call local HTTP server AND persist to SharedPreferences
    if (useFfi) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ffi_library_name', libraryName);
        if (libraryDescription != null)
          await prefs.setString('ffi_library_description', libraryDescription);
        await prefs.setString('ffi_profile_type', profileType);
        if (latitude != null) await prefs.setDouble('ffi_latitude', latitude);
        if (longitude != null)
          await prefs.setDouble('ffi_longitude', longitude);
        if (shareLocation != null)
          await prefs.setBool('ffi_share_location', shareLocation);

        // Call local HTTP server to persist in database (creates library_config AND library entries)
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'),
        );
        final response = await localDio.post(
          '/api/setup',
          data: {
            'library_name': libraryName,
            'library_description': libraryDescription,
            'profile_type': profileType,
            'theme': theme,
            'latitude': latitude,
            'longitude': longitude,
            'share_location': shareLocation,
          },
        );

        if (response.statusCode == 200 && response.data['success'] == true) {
          final data = response.data;
          if (data['user_id'] != null) {
            await _authService.saveUserId(data['user_id']);
          }
          if (data['library_id'] != null) {
            await _authService.saveLibraryId(data['library_id']);
          }
        }
        return response;
      } catch (e) {
        debugPrint('❌ setup error: $e');
        rethrow;
      }
    }
    final response = await _dio.post(
      '/api/setup',
      data: {
        'library_name': libraryName,
        'library_description': libraryDescription,
        'profile_type': profileType,
        'theme': theme,
        'latitude': latitude,
        'longitude': longitude,
        'share_location': shareLocation,
      },
    );

    if (response.statusCode == 200 && response.data['success'] == true) {
      // Save returned user_id and library_id to secure storage
      final data = response.data;
      if (data['user_id'] != null) {
        await _authService.saveUserId(data['user_id']);
      }
      if (data['library_id'] != null) {
        await _authService.saveLibraryId(data['library_id']);
      }
    }
    return response;
  }

  Future<Response> resetApp() async {
    if (useFfi) {
      // Call the FFI reset function which deletes all data from all tables
      try {
        final message = await RustLib.instance.api.crateApiFrbResetApp();
        return Response(
          requestOptions: RequestOptions(path: '/api/reset'),
          statusCode: 200,
          data: {'success': true, 'message': message},
        );
      } catch (e) {
        return Response(
          requestOptions: RequestOptions(path: '/api/reset'),
          statusCode: 500,
          data: {'success': false, 'message': e.toString()},
        );
      }
    }
    return await _dio.post('/api/reset');
  }

  Future<Response> searchOpenLibrary({
    String? title,
    String? author,
    String? subject,
  }) async {
    final queryParams = <String, dynamic>{};
    if (title != null && title.isNotEmpty) queryParams['title'] = title;
    if (author != null && author.isNotEmpty) queryParams['author'] = author;
    if (subject != null && subject.isNotEmpty) queryParams['subject'] = subject;

    return await _dio.get(
      '/api/integrations/openlibrary/search',
      queryParameters: queryParams,
    );
  }

  Future<Response> updateProfile({required Map<String, dynamic> data}) async {
    // In FFI/offline mode, profile is stored locally only
    if (useFfi) {
      if (data['fallback_preferences'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'ffi_fallback_preferences',
          jsonEncode(data['fallback_preferences']),
        );
      }
      if (data['api_keys'] != null) {
        final prefs = await SharedPreferences.getInstance();
        // Merge with existing keys
        final existing = prefs.getString('ffi_api_keys');
        final Map<String, dynamic> merged =
            existing != null
                ? Map<String, dynamic>.from(jsonDecode(existing))
                : <String, dynamic>{};
        (data['api_keys'] as Map).forEach((key, value) {
          if (value == null || value.toString().isEmpty) {
            merged.remove(key);
          } else {
            merged[key.toString()] = value;
          }
        });
        await prefs.setString('ffi_api_keys', jsonEncode(merged));
      }
      // Ensure server is running before making HTTP request
      final serverAvailable = await ensureServerRunning();
      if (!serverAvailable) {
        debugPrint('❌ updateProfile: embedded HTTP server not available');
        // Return a fake success since SharedPreferences was saved
        return Response(
          requestOptions: RequestOptions(path: '/api/profile'),
          statusCode: 200,
          data: {'message': 'Profile saved locally (server unavailable)'},
        );
      }
      // Call local HTTP server to persist in database
      try {
        final localDio = Dio(
          BaseOptions(
            baseUrl: 'http://127.0.0.1:$httpPort',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        return await localDio.put('/api/profile', data: data);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          markServerUnhealthy();
        }
        debugPrint('❌ updateProfile DioError: ${e.type} - ${e.message}');
        // Return success since SharedPreferences was saved
        return Response(
          requestOptions: RequestOptions(path: '/api/profile'),
          statusCode: 200,
          data: {'message': 'Profile saved locally (server error)'},
        );
      } catch (e) {
        debugPrint('❌ updateProfile local error: $e');
        // Return success since SharedPreferences was saved
        return Response(
          requestOptions: RequestOptions(path: '/api/profile'),
          statusCode: 200,
          data: {'message': 'Profile saved locally'},
        );
      }
    }
    return await _dio.put('/api/profile', data: data);
  }

  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) async {
    // Use FFI for native platforms
    if (useFfi) {
      return FfiService().getBooks(status: status, title: title, tag: tag);
    }

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
        if (response.data is Map && response.data['books'] is List) {
          final List<dynamic> data = response.data['books'];
          return data.map((json) => Book.fromJson(json)).toList();
        } else {
          if (kDebugMode) {
            debugPrint(
              '⚠️ getBooks: Unexpected response format: ${response.data}',
            );
          }
          return [];
        }
      } else {
        throw Exception(
          'Failed to load books (Status: ${response.statusCode})',
        );
      }
    } catch (e) {
      throw Exception('Failed to load books: $e');
    }
  }

  /// Find a book by ISBN in the local library
  /// Returns the book if found, null otherwise
  Future<Book?> findBookByIsbn(String isbn) async {
    if (isbn.isEmpty) return null;
    final cleanIsbn = isbn.replaceAll(RegExp(r'[^0-9X]'), '');
    if (cleanIsbn.length != 10 && cleanIsbn.length != 13) return null;

    try {
      final books = await getBooks();
      return books.firstWhere(
        (b) =>
            b.isbn != null &&
            b.isbn!.replaceAll(RegExp(r'[^0-9X]'), '') == cleanIsbn,
        orElse: () => throw StateError('Not found'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Get a list of all unique authors from existing books
  Future<List<String>> getAllAuthors() async {
    try {
      final books = await getBooks();
      final Set<String> authors = {};
      for (final book in books) {
        if (book.author != null && book.author!.isNotEmpty) {
          // Split by comma or semicolon to handle multiple authors
          final split = book.author!.split(RegExp(r'[,;]\s*'));
          for (var a in split) {
            final trimmed = a.trim();
            if (trimmed.isNotEmpty) {
              authors.add(trimmed);
            }
          }
        }
      }
      final list = authors.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return list;
    } catch (e) {
      debugPrint('Error fetching all authors: $e');
      return [];
    }
  }

  Future<Book> getBook(int id) async {
    // Use FFI for native platforms
    if (useFfi) {
      return FfiService().getBook(id);
    }

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
    if (useFfi) {
      try {
        await FfiService().reorderBooks(bookIds);
        return;
      } catch (e) {
        debugPrint('FFI reorderBooks error: $e');
        rethrow;
      }
    }
    try {
      await _dio.patch('/api/books/reorder', data: {'book_ids': bookIds});
    } catch (e) {
      debugPrint('Error reordering books: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> lookupBook(
    String isbn, {
    Locale? locale,
  }) async {
    // Use backend API for lookup to respect enabled sources (OpenLibrary, Inventaire, etc.)
    // In FFI mode, use the local HTTP server directly.

    try {
      // Ensure embedded HTTP server is running (required for FFI mode)
      if (useFfi) {
        final serverAvailable = await ensureServerRunning();
        if (!serverAvailable) {
          debugPrint('❌ Lookup failed: embedded HTTP server not available');
          return null;
        }
      }

      final currentLang = locale?.languageCode ?? 'en';
      // Use a dedicated Dio instance with longer timeout for lookups
      // The backend may chain BNF → Inventaire → OpenLibrary → Google Books,
      // which can take 15+ seconds for difficult ISBNs
      final lookupDio = Dio(
        BaseOptions(
          baseUrl: useFfi ? 'http://127.0.0.1:$httpPort' : _dio.options.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final response = await lookupDio.get(
        '/api/lookup/$isbn',
        queryParameters: {'lang': currentLang},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        return {
          'title': data['title'],
          'author': data['authors'] != null
              ? (data['authors'] as List)
                    .map((a) => a is String ? a : a['name'])
                    .where((a) {
                      if (a == null) return false;
                      final lower = a.toString().toLowerCase();
                      return lower != 'unknown author' && lower != 'unknown';
                    })
                    .join(', ')
              : null,
          'authors_data': data['authors'], // Pass full data for UI
          'publisher': data['publisher'],
          'year': data['publication_year'] != null
              ? int.tryParse(data['publication_year'].toString())
              : null,
          'cover_url': data['cover_url'],
          'summary': data['summary'],
        };
      }
    } catch (e) {
      debugPrint('Lookup API Error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchBooks({
    String? query,
    String? title,
    String? author,
    String? publisher,
    String? subject,
    String?
    lang, // User's preferred language for relevance boost (e.g., "fr", "en")
    String?
    source, // Filter to specific source(s): "inventaire", "bnf", "openlibrary" (comma-separated)
    bool autocomplete = false,
  }) async {
    try {
      // Ensure embedded HTTP server is running (auto-restart if needed)
      if (useFfi) {
        final serverAvailable = await ensureServerRunning();
        if (!serverAvailable) {
          debugPrint('❌ Search failed: embedded HTTP server not available');
          return [];
        }
      }

      final queryParams = <String, dynamic>{};
      if (query != null && query.isNotEmpty) queryParams['q'] = query;
      if (title != null && title.isNotEmpty) queryParams['title'] = title;
      if (author != null && author.isNotEmpty) queryParams['author'] = author;
      if (publisher != null && publisher.isNotEmpty)
        queryParams['publisher'] = publisher;
      if (subject != null && subject.isNotEmpty)
        queryParams['subject'] = subject;
      if (lang != null && lang.isNotEmpty) queryParams['lang'] = lang;
      if (source != null && source.isNotEmpty) queryParams['source'] = source;
      if (autocomplete) queryParams['autocomplete'] = true;

      // Use a new Dio instance with longer timeout for external search
      // External sources (Inventaire, OpenLibrary, BNF) can take 12+ seconds
      // OpenLibrary in particular averages 7-18s for some queries
      final searchDio = useFfi
          ? Dio(
              BaseOptions(
                baseUrl: 'http://127.0.0.1:$httpPort',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            )
          : Dio(
              BaseOptions(
                baseUrl: _dio.options.baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

      final response = await searchDio.get(
        '/api/integrations/search_unified',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } on DioException catch (e) {
      // Mark server as unhealthy on connection errors so next call will try restart
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        markServerUnhealthy();
      }
      debugPrint('Search API DioError: ${e.type} - ${e.message}');
    } catch (e) {
      debugPrint('Search API Error: $e');
    }
    return [];
  }

  Future<Response> getTranslations(String locale) async {
    return await _dio.get('$hubUrl/api/translations/$locale');
  }

  /// Get MCP configuration for AI Assistant integrations (Claude Desktop, Cursor, etc.)
  /// Returns dynamic paths based on the running server's actual location
  Future<Response> getMcpConfig() async {
    if (useFfi) {
      // In FFI mode, call the local HTTP server
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.get('/api/integrations/mcp-config');
    }
    return await _dio.get('/api/integrations/mcp-config');
  }

  Future<List<Tag>> getTags() async {
    // Use FFI for native platforms
    if (useFfi) {
      return FfiService().getTags();
    }

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

  Future<Tag> createTag(String name, {int? parentId}) async {
    if (useFfi) {
      return FfiService().createTag(name, parentId: parentId);
    }
    final response = await _dio.post(
      '/api/tags',
      data: {'name': name, 'parent_id': parentId},
    );
    return Tag.fromJson(response.data['tag']);
  }

  Future<Tag> updateTag(int id, String name, {int? parentId}) async {
    if (useFfi) {
      return FfiService().updateTag(id, name, parentId: parentId);
    }
    final response = await _dio.put(
      '/api/tags/$id',
      data: {'name': name, 'parent_id': parentId},
    );
    return Tag.fromJson(response.data['tag']);
  }

  Future<void> deleteTag(int id) async {
    if (useFfi) {
      return FfiService().deleteTag(id);
    }
    await _dio.delete('/api/tags/$id');
  }

  // ============ P2P Device Pairing ============

  /// Generate a pairing code on this device (Source) by calling the local backend.
  Future<Response> generatePairingCode({
    required String uuid,
    required String secret,
    required String ip,
  }) async {
    // Try 127.0.0.1 first (standard IPv4)
    try {
      final localDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$httpPort'));
      return await localDio.post(
        '/api/auth/pairing/code',
        data: {'uuid': uuid, 'secret': secret, 'ip': ip},
      );
    } catch (e) {
      // If 127.0.0.1 fails, try localhost (might resolve to ::1 IPv6)
      debugPrint(
        '⚠️ generatePairingCode: 127.0.0.1 failed ($e), trying localhost...',
      );
      try {
        final localDioFallback = Dio(
          BaseOptions(baseUrl: 'http://localhost:$httpPort'),
        );
        return await localDioFallback.post(
          '/api/auth/pairing/code',
          data: {'uuid': uuid, 'secret': secret, 'ip': ip},
        );
      } catch (e2) {
        debugPrint('❌ generatePairingCode: localhost also failed: $e2');
        rethrow;
      }
    }
  }

  /// Verify a pairing code on a remote peer (Target wants to join Source).
  Future<Response> verifyRemotePairingCode({
    required String host,
    required String code,
  }) async {
    debugPrint('🔗 Pairing: Attempting to verify code on http://$host');
    try {
      final remoteDio = Dio(
        BaseOptions(
          baseUrl: 'http://$host',
          connectTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final response = await remoteDio.post(
        '/api/auth/pairing/verify',
        data: {'code': code},
      );
      debugPrint(
        '🔗 Pairing: Response status=${response.statusCode}, data=${response.data}',
      );
      return response;
    } on DioException catch (e) {
      debugPrint('🔗 Pairing ERROR: ${e.type} - ${e.message}');
      // Return a fake response with error info for display
      return Response(
        requestOptions: RequestOptions(path: '/api/auth/pairing/verify'),
        statusCode: 500,
        data: {'error': 'Connection failed: ${e.message ?? e.type}'},
      );
    }
  }

  /// Import full library data from a remote peer after successful pairing.
  /// Downloads all books, contacts, tags from the peer and imports them locally.
  Future<Map<String, dynamic>> importFromPeer(String host) async {
    debugPrint('📥 Sync: Starting full import from http://$host');
    final normalizedHost = host.startsWith('http') ? host : 'http://$host';

    try {
      final remoteDio = Dio(
        BaseOptions(
          baseUrl: normalizedHost,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      // Fetch full export from peer
      final res = await remoteDio.get('/api/export');
      if (res.statusCode != 200) {
        throw Exception('Export failed with status ${res.statusCode}');
      }

      final data = res.data as Map<String, dynamic>;
      int booksImported = 0;
      int contactsImported = 0;
      int tagsImported = 0;

      // Import books
      if (data['books'] != null) {
        final books = data['books'] as List;
        for (final bookData in books) {
          try {
            // Create book via local API
            await createBook(bookData);
            booksImported++;
          } catch (e) {
            debugPrint('📥 Sync: Failed to import book: $e');
          }
        }
      }

      // Import contacts
      if (data['contacts'] != null) {
        final contacts = data['contacts'] as List;
        for (final contactData in contacts) {
          try {
            await createContact(contactData);
            contactsImported++;
          } catch (e) {
            debugPrint('📥 Sync: Failed to import contact: $e');
          }
        }
      }

      // Note: Tags are imported as part of book data, no need to import separately

      debugPrint(
        '📥 Sync: Import complete - Books: $booksImported, Contacts: $contactsImported, Tags: $tagsImported',
      );

      return {
        'success': true,
        'books': booksImported,
        'contacts': contactsImported,
        'tags': tagsImported,
      };
    } catch (e) {
      debugPrint('📥 Sync ERROR: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Relay Hub ────────────────────────────────────────────────────────

  /// Set up a relay mailbox on the given hub URL.
  Future<Response> setupRelay({required String relayUrl}) async {
    if (kDebugMode) debugPrint('Relay setup: POST /api/peers/relay/setup');
    try {
      final Response resp;
      if (useFfi) {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
        );
        resp = await localDio.post(
          '/api/peers/relay/setup',
          data: {'relay_url': relayUrl},
        );
      } else {
        resp = await _dio.post(
          '/api/peers/relay/setup',
          data: {'relay_url': relayUrl},
        );
      }
      debugPrint('Relay setup: ${resp.statusCode} ${resp.data}');
      return resp;
    } catch (e) {
      debugPrint('Relay setup failed: $e');
      rethrow;
    }
  }

  /// Get current relay configuration (if any).
  Future<Response> getRelayConfig() async {
    if (useFfi) {
      final localDio = Dio(
        BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
      );
      return localDio.get('/api/peers/relay/config');
    }
    return _dio.get('/api/peers/relay/config');
  }

  /// Disconnect from relay hub (delete local relay config).
  Future<Response> disconnectRelay() async {
    if (useFfi) {
      final localDio = Dio(
        BaseOptions(baseUrl: 'http://localhost:${ApiService.httpPort}'),
      );
      return localDio.delete('/api/peers/relay/config');
    }
    return _dio.delete('/api/peers/relay/config');
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final ApiService apiService;
  // Prevent infinite loops or concurrent discovery attempts
  static bool _isDiscovering = false;

  RetryInterceptor(this.dio, this.apiService);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only attempt recovery for connection errors or timeouts
    bool shouldRetry =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (err.error != null &&
            err.error.toString().contains('Connection refused'));

    if (!shouldRetry || _isDiscovering) {
      return handler.next(err);
    }

    // Skip port discovery for requests to external services (Hub, etc.)
    // These are identified by having a full URL in the path or targeting a different host
    final requestPath = err.requestOptions.path;
    final requestUri = err.requestOptions.uri.toString();
    final currentBaseUrl = dio.options.baseUrl;

    // If the path is a full URL (starts with http), check if it's targeting our backend
    if (requestPath.startsWith('http://') ||
        requestPath.startsWith('https://')) {
      // Extract port from the full URL path
      final pathUri = Uri.tryParse(requestPath);
      final baseUri = Uri.tryParse(currentBaseUrl);

      // If it's targeting a different port/host, don't try to "fix" it with port discovery
      if (pathUri != null && baseUri != null) {
        if (pathUri.host != baseUri.host || pathUri.port != baseUri.port) {
          debugPrint(
            '⚠️ Connection failed on $requestPath (external service). Skipping port discovery.',
          );
          return handler.next(err);
        }
      }
    }

    _isDiscovering = true;
    debugPrint(
      '⚠️ Connection failed on $requestUri. Initiating Smart Port Discovery... 🕵️',
    );

    try {
      // Ports to scan: 8000 to 8010
      for (int port = 8000; port <= 8010; port++) {
        final testUrl = 'http://localhost:$port';

        // Skip current failed URL to avoid redundancy if it was one of these
        // if (err.requestOptions.baseUrl.contains(port.toString())) continue;

        debugPrint('   → Probing $testUrl...');
        try {
          // Create a raw dio instance for probing to avoid interceptors
          final probeDio = Dio(
            BaseOptions(
              baseUrl: testUrl,
              connectTimeout: const Duration(milliseconds: 500),
              receiveTimeout: const Duration(milliseconds: 500),
            ),
          );

          // Try simple health check or root
          final response = await probeDio.get(
            '/api/books?limit=1',
          ); // Light query

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

      debugPrint(
        '❌ Smart Port Discovery failed. Backend unreachable on ports 8000-8010.',
      );
    } finally {
      _isDiscovering = false;
    }

    return handler.next(err);
  }
}
