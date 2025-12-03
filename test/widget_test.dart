// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:app/main.dart';
import 'package:app/providers/theme_provider.dart';

import 'dart:io';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:app/services/backend_service.dart';

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class MockBackendService extends BackendService {
  @override
  Future<void> start() async {}
  
  @override
  Future<void> stop() async {}
  
  @override
  bool get isRunning => false;
  
  @override
  int? get port => null;
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = TestHttpOverrides();
    await dotenv.load(fileName: ".env");
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(
        themeProvider: ThemeProvider(),
        backendService: MockBackendService(),
      ));
      await tester.pumpAndSettle();

      // Verify that our app starts
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
