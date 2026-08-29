import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/api_service.dart';

/// The port-conflict warning tells the user another application holds the
/// embedded server's usual port. It used to fire whenever the server had not
/// obtained that port, without checking who held it, and on Android the holder
/// was almost always the app's own listener surviving an activity restart.
///
/// These tests lock the two halves of the fix: the occupant is identified from
/// its `/api/health` answer, and the warning is raised only for a foreign one.
void main() {
  final defaultPort = ApiService.defaultHttpPort;

  setUp(() {
    ApiService.httpPort = defaultPort;
    ApiService.defaultPortHeldByForeignApp = false;
  });

  tearDown(() {
    ApiService.httpPort = defaultPort;
    ApiService.defaultPortHeldByForeignApp = false;
  });

  /// A loopback server answering [body] as JSON on `/api/health`.
  Future<HttpServer> serveHealth(Map<String, dynamic> body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await req.response.close();
    });
    return server;
  }

  group('probePortHeldByForeignApp', () {
    test('a BiblioGenius backend on the port is not a foreign app', () async {
      final server = await serveHealth({
        'status': 'ok',
        'service': 'bibliogenius',
        'version': '1.0.0',
      });
      addTearDown(() => server.close(force: true));

      expect(
        await ApiService.probePortHeldByForeignApp(server.port),
        isFalse,
      );
    });

    test('any other service on the port is foreign', () async {
      final server = await serveHealth({'service': 'some-other-daemon'});
      addTearDown(() => server.close(force: true));

      expect(await ApiService.probePortHeldByForeignApp(server.port), isTrue);
    });

    test('a port nothing listens on reads as foreign', () async {
      // Bind then release to obtain a port that is free right now.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final freePort = probe.port;
      await probe.close(force: true);

      expect(await ApiService.probePortHeldByForeignApp(freePort), isTrue);
    });
  });

  group('refreshPortConflictDiagnosis', () {
    test('clears the verdict when the preferred port was obtained', () async {
      ApiService.defaultPortHeldByForeignApp = true;
      ApiService.httpPort = defaultPort;

      await ApiService.refreshPortConflictDiagnosis();

      expect(ApiService.defaultPortHeldByForeignApp, isFalse);
    });
  });

  group('shouldWarnAboutPortConflict', () {
    test('silent while the server holds its preferred port', () {
      ApiService.httpPort = defaultPort;
      ApiService.defaultPortHeldByForeignApp = true;

      expect(ApiService.shouldWarnAboutPortConflict, isFalse);
    });

    test('silent when the port moved but the occupant is one of ours', () {
      // The Android relaunch case: the previous listener of this very app still
      // holds the port. Accusing "another application" would be a lie.
      ApiService.httpPort = defaultPort + 1;
      ApiService.defaultPortHeldByForeignApp = false;

      expect(ApiService.shouldWarnAboutPortConflict, isFalse);
    });

    test('warns when the port moved and a foreign app holds it', () {
      ApiService.httpPort = defaultPort + 1;
      ApiService.defaultPortHeldByForeignApp = true;

      expect(ApiService.shouldWarnAboutPortConflict, isTrue);
    });
  });
}
