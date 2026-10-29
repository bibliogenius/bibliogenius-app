import 'dart:typed_data';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request with an empty JSON object and records where it went.
class _RecordingAdapter implements HttpClientAdapter {
  final List<Uri> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'HUB_URL=https://hub.example.test');
  });

  test(
    'HTTP mode sends the bulk approval to the backend base URL, not the hub',
    () async {
      // The route lives on the Rust backend only. In HTTP mode (web, Docker
      // backend) the request must follow the configured base URL.
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final api = ApiService(
        AuthService(),
        baseUrl: 'http://backend.example.test:8001',
        dio: dio,
      );

      await api.autoApproveAllPeers();

      expect(adapter.requested, hasLength(1));
      expect(
        adapter.requested.single.toString(),
        'http://backend.example.test:8001/api/peers/auto_approve_all',
      );
    },
  );
}
