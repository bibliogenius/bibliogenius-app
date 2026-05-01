// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:bibliogenius/main.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';
import 'package:network_image_mock/network_image_mock.dart';

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = TestHttpOverrides();
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      // Ignore missing .env in tests/CI
    }
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final scheduler = BackupSchedulerService.production(
      prefs: prefs,
      authService: AuthService(),
    );
    addTearDown(scheduler.dispose);

    await mockNetworkImagesFor(() async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        MyApp(
          themeProvider: ThemeProvider(),
          useFfi: false,
          envConfig: const {},
          backupScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();

      // Verify that our app starts
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
