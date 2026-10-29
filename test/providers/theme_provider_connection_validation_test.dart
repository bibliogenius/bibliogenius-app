import 'dart:io';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;
}

/// Stands in for the app-wide ApiService (the FFI one from main.dart) and
/// records the bulk approval calls it receives.
class _RecordingApiService extends ApiService {
  _RecordingApiService()
    : super(AuthService(), baseUrl: 'http://localhost:0', useFfi: true);

  int autoApproveCalls = 0;
  bool autoApproveThrows = false;

  @override
  Future<Response> autoApproveAllPeers() async {
    autoApproveCalls++;
    if (autoApproveThrows) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/peers/auto_approve_all'),
      );
    }
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/auto_approve_all'),
      statusCode: 200,
      data: {'approved': 2},
    );
  }

  @override
  Future<Response> updateProfile({required Map<String, dynamic> data}) async =>
      Response(
        requestOptions: RequestOptions(path: '/api/profile'),
        statusCode: 200,
        data: {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUpAll(() {
    tempRoot = Directory.systemTemp.createTempSync(
      'connection_validation_prefs_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempRoot.path);
    // The modules sync builds its own ApiService, whose default base URL
    // reads the (empty) environment.
    dotenv.testLoad(fileInput: '');
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeProvider.setConnectionValidationEnabled', () {
    test(
      'disabling validation bulk-approves through the given ApiService',
      () async {
        // The bulk approval is a local-server route. A provider-built
        // ApiService would miss the FFI flag and send it to the hub, where it
        // does not exist: the pending requests would stay pending.
        final api = _RecordingApiService();
        final provider = ThemeProvider();
        await provider.loadSettings();

        await provider.setConnectionValidationEnabled(false, apiService: api);

        expect(api.autoApproveCalls, 1);
        expect(provider.connectionValidationEnabled, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('connectionValidationEnabled'), isFalse);
      },
    );

    test('enabling validation does not touch pending requests', () async {
      final api = _RecordingApiService();
      final provider = ThemeProvider();
      await provider.loadSettings();

      await provider.setConnectionValidationEnabled(true, apiService: api);

      expect(api.autoApproveCalls, 0);
      expect(provider.connectionValidationEnabled, isTrue);
    });

    test('a failed bulk approval still saves the setting', () async {
      final api = _RecordingApiService()..autoApproveThrows = true;
      final provider = ThemeProvider();
      await provider.loadSettings();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setConnectionValidationEnabled(false, apiService: api);

      expect(api.autoApproveCalls, 1);
      expect(provider.connectionValidationEnabled, isFalse);
      expect(notifications, greaterThanOrEqualTo(1));
    });
  });
}
