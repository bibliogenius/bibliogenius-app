import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliogenius/screens/scan_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/mock_classes.dart';

// Helper for GoRouter testing
class MockGoRouter {
  String? lastLocation;
  Object? lastExtra;
}

void main() {
  group('ScanScreen Flow', () {
    late MockApiService mockApi;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
      // Reset mock data if needed
    });

    testWidgets('renders correctly and handles manual entry', (
      WidgetTester tester,
    ) async {
      // debugDumpApp(); // Only if needed for debugging

      // We assume MobileScanner might fail to init in test,
      // but usually it just sits there or throws.
      // If it throws, we might need to handle it.
      // We'll try to run it.

      final mockRouter = MockGoRouter();

      final router = GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(
            path: '/scan',
            builder: (context, state) => ScanScreen(
              scannerBuilder: (ctx, ctrl, onDetect) =>
                  const SizedBox.expand(key: Key('mockScanner')),
              controller: MockMobileScannerController(),
            ),
          ),
          GoRoute(
            path: '/books/add',
            builder: (context, state) {
              mockRouter.lastLocation = '/books/add';
              mockRouter.lastExtra = state.extra;
              return const SizedBox();
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiService>.value(value: mockApi),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            // TranslationService usually relies on Localizations,
            // verifying context.
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      // Verify Screen Title
      // It might be 'Scan ISBN' or translated key.
      // ScanScreen usage: TranslationService.translate(context, 'scan_isbn_title')
      // Note: TranslationService usually needs setup ->
      // Since we didn't mock TranslationService, it might return null or key.
      // Let's assume it returns key or null if not set up.
      // Let's look for known widgets like Icons.

      expect(find.byIcon(Icons.flash_off), findsOneWidget); // Torch icon
      expect(find.byIcon(Icons.cameraswitch), findsOneWidget);
      expect(find.byKey(const Key('mockScanner')), findsOneWidget);
      await tester.pumpAndSettle(); // Ensure everything is settled
      // debugDumpApp();

      // Verify buttons exist
      expect(find.byType(CustomPaint), findsWidgets); // Should find the overlay
      expect(find.byType(ElevatedButton), findsWidgets);
      // expect(find.text('HELLO WORLD MANUAL'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard), findsOneWidget);

      // Verify "Enter Manually" button
      // It's an ElevatedButton with icon keyboard
      // final manualBtn = find.text('Enter Manually');
      // Or by icon
      // expect(find.byIcon(Icons.keyboard), findsOneWidget);
      // expect(manualBtn, findsOneWidget); // Translation might return null if Provider mock defaults are empty.

      // Tap the button (find by Type and Icon to be sure)
      final btnFinder = find.widgetWithIcon(ElevatedButton, Icons.keyboard);
      // expect(btnFinder, findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle(); // Wait for navigation

      // Should have navigated to /books/add
      expect(mockRouter.lastLocation, '/books/add');
      // Extra should be null for "Enter Manually" via bottom button (it just goes to add screen)
      // Wait, ScanScreen code:
      // onPressed: () { context.push('/books/add'); },
      expect(mockRouter.lastExtra, null);

      // Verify instruction text (translate returns the key when no PO files are loaded)
      expect(find.textContaining('scan_instruction', skipOffstage: false), findsOneWidget);
    });
  });
}
