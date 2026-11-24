import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';

class _MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake_token';
}

/// A pairing made after the hub registration was declined (ADR-073) stays
/// on the local network: the peer's relay credentials are neither used nor
/// kept, and no relay mailbox is created for this library.
///
/// `connectLocalPeer` talks to the embedded local server and to the peer
/// through its own Dio instances, so two loopback servers stand in for
/// them. The machine running the test may or may not have a LAN address;
/// both outcomes are covered by what is asserted.
void main() {
  // No widget binding here: it would replace the HTTP client with one that
  // answers 400 to everything, loopback included.

  late HttpServer local;
  late HttpServer peer;
  late ApiService api;

  /// (path, decoded body) of every request the embedded server received.
  final localRequests = <(String, Map<String, dynamic>)>[];

  Future<Map<String, dynamic>> body(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    if (raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  void reply(HttpRequest req, Map<String, dynamic> data) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    req.response.close();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'libraryName': 'Mine'});
    localRequests.clear();

    local = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    local.listen((req) async {
      localRequests.add((req.uri.path, await body(req)));
      // A library that never registered: keys, no relay configuration.
      reply(req, {
        'library_name': 'Mine',
        'library_uuid': 'my-uuid',
        'ed25519_public_key': 'my-ed',
        'x25519_public_key': 'my-x',
      });
    });

    // The peer answers the handshake with its own relay credentials, as a
    // registered library does.
    peer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    peer.listen((req) async {
      await body(req);
      reply(req, {
        'library_uuid': 'peer-uuid',
        'ed25519_public_key': 'peer-ed',
        'x25519_public_key': 'peer-x',
        'relay_url': 'http://127.0.0.1:${peer.port}',
        'mailbox_id': 'peer-mailbox',
        'relay_write_token': 'peer-token',
      });
    });

    ApiService.httpPort = local.port;
    api = ApiService(
      _MockAuthService(),
      baseUrl: 'http://localhost:8001',
      useFfi: true,
    );
  });

  tearDown(() async {
    await local.close(force: true);
    await peer.close(force: true);
  });

  Future<void> pair({required bool localOnly}) => api.connectPeer(
    'Peer',
    'http://127.0.0.1:${peer.port}',
    libraryUuid: 'peer-uuid',
    // An invitation or a QR code carries these.
    relayUrl: 'http://127.0.0.1:${peer.port}',
    mailboxId: 'peer-mailbox',
    relayWriteToken: 'peer-token',
    localOnly: localOnly,
  );

  Iterable<Map<String, dynamic>> savedPeers() => localRequests
      .where((r) => r.$1 == '/api/peers/connect')
      .map((r) => r.$2);

  bool relaySetUp() =>
      localRequests.any((r) => r.$1 == '/api/peers/relay/setup');

  test('local only: no relay mailbox is created, and the peer is saved '
      'without any way to it through the hub', () async {
    await pair(localOnly: true);

    expect(relaySetUp(), isFalse);
    for (final saved in savedPeers()) {
      expect(saved.containsKey('relay_url'), isFalse);
      expect(saved.containsKey('mailbox_id'), isFalse);
      expect(saved.containsKey('relay_write_token'), isFalse);
    }
  });

  test('with the hub: the peer is saved with its relay credentials', () async {
    // The control: the same call keeps the credentials, so the assertions
    // above are about the flag and not about this harness.
    await pair(localOnly: false);

    expect(savedPeers(), isNotEmpty);
    for (final saved in savedPeers()) {
      expect(saved['relay_url'], isNotNull);
      expect(saved['mailbox_id'], 'peer-mailbox');
    }
  });
}
