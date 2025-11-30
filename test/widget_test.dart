// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/providers/theme_provider.dart';

import 'dart:io';
import 'package:network_image_mock/network_image_mock.dart';

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });

  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(themeProvider: ThemeProvider()));

      // Verify that our counter starts at 0.
      // Note: The default app template has a counter, but our app might not.
      // We should check if the app starts successfully instead.
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
