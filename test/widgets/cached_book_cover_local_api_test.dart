import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A relative `/api` cover (a peer's photographed cover through the local
/// cover proxy) must be loaded from the embedded server, on the port it
/// really listens on. The Dio base URL comes from `.env` and is not that
/// server in the native app: loading from it made every peer's
/// photographed cover fail while covers from the web showed.
Future<String> _loadedUrl(
  WidgetTester tester, {
  required bool useFfi,
  required String imageUrl,
}) async {
  final api = ApiService(
    AuthService(),
    baseUrl: 'http://localhost:8001',
    useFfi: useFfi,
  );
  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: api,
      child: MaterialApp(
        home: Scaffold(
          body: CachedBookCover(
            imageUrl: imageUrl,
            width: 40,
            height: 60,
            isPeerCover: true,
            semanticLabel: null,
          ),
        ),
      ),
    ),
  );
  return tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .imageUrl;
}

void main() {
  const proxied =
      '/api/peers/cover-proxy?peer_url=http%3A%2F%2F192.168.1.10%3A8000'
      '&book_id=01a2113b-ffbf-75d1-9855-6b1681810f37';

  late int savedPort;
  setUp(() => savedPort = ApiService.httpPort);
  tearDown(() => ApiService.httpPort = savedPort);

  testWidgets('in the native app a relative cover is read from the embedded '
      'server port', (tester) async {
    ApiService.httpPort = 8010;

    final url = await _loadedUrl(tester, useFfi: true, imageUrl: proxied);

    expect(url, 'http://127.0.0.1:8010$proxied');
  });

  testWidgets('without the embedded server a relative cover keeps the '
      'configured base URL', (tester) async {
    ApiService.httpPort = 8010;

    final url = await _loadedUrl(tester, useFfi: false, imageUrl: proxied);

    expect(url, 'http://localhost:8001$proxied');
  });

  testWidgets('an absolute cover URL is loaded as given', (tester) async {
    const web = 'https://covers.openlibrary.org/b/isbn/1-M.jpg';

    final url = await _loadedUrl(tester, useFfi: true, imageUrl: web);

    expect(url, web);
  });
}
