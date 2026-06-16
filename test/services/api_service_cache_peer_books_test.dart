import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';

class _MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

/// `cachePeerBooks` posts to the embedded local server using its own internal
/// Dio, so the usual http_mock_adapter seam does not intercept it. We stand up
/// a real loopback HTTP server, point `ApiService.httpPort` at it, and capture
/// the request body to lock the `is_full_snapshot` wire contract that gates the
/// backend's delete-absent pass (cache-drain guard).
void main() {
  late HttpServer server;
  late ApiService api;
  Map<String, dynamic>? lastBody;

  setUp(() async {
    lastBody = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      lastBody = jsonDecode(raw) as Map<String, dynamic>;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'count': 1, 'peer_id': 1}));
      await req.response.close();
    });
    ApiService.httpPort = server.port;
    // baseUrl is passed only to skip the dotenv lookup in the constructor
    // (same boilerplate as api_service_test.dart). cachePeerBooks does not use
    // it: it builds its own Dio against httpPort (set above), which is where
    // the loopback server actually receives the request.
    api = ApiService(_MockAuthService(), baseUrl: 'http://localhost:8001');
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('cachePeerBooks is_full_snapshot wire contract', () {
    final books = [Book(title: 'Alpha', isbn: '111')];

    test('defaults to false (additive) when not specified', () async {
      await api.cachePeerBooks(1, books);
      expect(
        lastBody?['is_full_snapshot'],
        false,
        reason: 'omitting the flag must default to a non-destructive merge',
      );
    });

    test('forwards true for a full snapshot', () async {
      await api.cachePeerBooks(1, books, isFullSnapshot: true);
      expect(lastBody?['is_full_snapshot'], true);
      expect((lastBody?['books'] as List).length, 1);
    });

    test('forwards false for a partial batch', () async {
      await api.cachePeerBooks(1, books, isFullSnapshot: false);
      expect(lastBody?['is_full_snapshot'], false);
    });
  });
}
