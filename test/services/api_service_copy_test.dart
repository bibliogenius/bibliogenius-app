import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/mock_classes.dart';

/// Custom interceptor to capture request data before it's sent
class RequestCaptureInterceptor extends Interceptor {
  Map<String, dynamic>? lastRequestData;
  String? lastRequestPath;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequestPath = options.path;
    lastRequestData = options.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(options.data)
        : null;
    // Return a mock response instead of making a real request
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'copy': {'id': 1},
          'message': 'Copy created',
        },
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late RequestCaptureInterceptor captureInterceptor;
  late ApiService apiService;
  late MockAuthService mockAuthService;

  setUp(() {
    // Initialize mock storage
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8001'));
    captureInterceptor = RequestCaptureInterceptor();
    dio.interceptors.add(captureInterceptor);

    mockAuthService = MockAuthService();
    apiService = ApiService(
      mockAuthService,
      dio: dio,
      baseUrl: 'http://localhost:8001',
    );
  });

  group('ApiService.createCopy enrichment', () {
    test('adds library_id and is_temporary when not provided', () async {
      // Call with minimal data (missing library_id and is_temporary)
      await apiService.createCopy({'book_id': 42, 'status': 'available'});

      // Verify enrichment
      expect(captureInterceptor.lastRequestData, isNotNull);
      expect(captureInterceptor.lastRequestData!['book_id'], 42);
      expect(captureInterceptor.lastRequestData!['status'], 'available');
      // library_id may be null when AuthService has no stored ID - backend resolves dynamically
      expect(
        captureInterceptor.lastRequestData!.containsKey('library_id'),
        true,
      );
      expect(
        captureInterceptor.lastRequestData!['is_temporary'],
        false,
      ); // Default
    });

    test('preserves library_id when explicitly provided', () async {
      // Call with explicit library_id
      await apiService.createCopy({
        'book_id': 42,
        'library_id': 5, // Explicitly provided
        'status': 'available',
      });

      // Verify library_id is NOT overwritten
      expect(captureInterceptor.lastRequestData!['library_id'], 5);
    });

    test(
      'preserves is_temporary:true when explicitly provided (borrowing use case)',
      () async {
        // Call with is_temporary: true (borrowing scenario)
        await apiService.createCopy({
          'book_id': 42,
          'status': 'borrowed',
          'is_temporary': true, // Explicitly provided - must NOT be overwritten
        });

        // Verify is_temporary is NOT overwritten to false
        expect(captureInterceptor.lastRequestData!['is_temporary'], true);
      },
    );

    test('preserves is_temporary:false when explicitly provided', () async {
      // Call with is_temporary: false explicitly
      await apiService.createCopy({
        'book_id': 42,
        'status': 'available',
        'is_temporary': false,
      });

      // Verify is_temporary stays false
      expect(captureInterceptor.lastRequestData!['is_temporary'], false);
    });

    test('handles all required fields for valid API request', () async {
      await apiService.createCopy({'book_id': 42, 'status': 'available'});

      // Verify all required fields are present
      expect(captureInterceptor.lastRequestData!.containsKey('book_id'), true);
      expect(
        captureInterceptor.lastRequestData!.containsKey('library_id'),
        true,
      );
      expect(captureInterceptor.lastRequestData!.containsKey('status'), true);
      expect(
        captureInterceptor.lastRequestData!.containsKey('is_temporary'),
        true,
      );
    });

    test('preserves additional optional fields', () async {
      // Call with optional fields
      await apiService.createCopy({
        'book_id': 42,
        'status': 'available',
        'notes': 'Test notes',
        'acquisition_date': '2024-01-15',
        'price': 19.99,
      });

      // Verify optional fields are preserved
      expect(captureInterceptor.lastRequestData!['notes'], 'Test notes');
      expect(
        captureInterceptor.lastRequestData!['acquisition_date'],
        '2024-01-15',
      );
      expect(captureInterceptor.lastRequestData!['price'], 19.99);
      // And required fields are still added
      expect(
        captureInterceptor.lastRequestData!.containsKey('library_id'),
        true,
      );
      expect(captureInterceptor.lastRequestData!['is_temporary'], false);
    });
  });
}
