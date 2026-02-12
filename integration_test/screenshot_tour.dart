/// Screenshot Tour — Automated UI walkthrough for UX/UI review.
///
/// Navigates through every major screen and captures a screenshot.
/// Run with:
///   flutter test integration_test/screenshot_tour.dart -d macos
///
/// Screenshots are saved to: integration_test/screenshots/
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bibliogenius/main.dart' as app;
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Use mock storage to avoid Keychain prompts
  AuthService.storage = MockSecureStorage();

  // Suppress expected image load errors (404 from OpenLibrary, etc.)
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    if (msg.contains('NetworkImageLoadException') ||
        msg.contains('HTTP request failed, statusCode: 404') ||
        msg.contains('RenderFlex overflowed')) {
      return;
    }
    FlutterError.presentError(details);
  };

  binding.platformDispatcher.onError = (error, stack) {
    if (error.toString().contains('NetworkImageLoadException') ||
        error.toString().contains('HTTP request failed, statusCode: 404')) {
      return true;
    }
    return false;
  };

  // --- Screenshot helper (macOS-compatible via RepaintBoundary) ---
  final screenshotDir = Directory('integration_test/screenshots');
  int screenshotIndex = 0;

  // Clean previous screenshots on start
  if (screenshotDir.existsSync()) {
    for (final file in screenshotDir.listSync()) {
      if (file is File && file.path.endsWith('.png')) {
        file.deleteSync();
      }
    }
  }

  Future<void> takeScreenshot(WidgetTester tester, String name) async {
    screenshotIndex++;
    final prefix = screenshotIndex.toString().padLeft(2, '0');
    final fileName = '${prefix}_$name';
    debugPrint('📸 Taking screenshot: $fileName');

    await tester.pumpAndSettle();

    // Find the root RenderRepaintBoundary
    final renderObject = tester.binding.rootElement!.renderObject!;
    RenderRepaintBoundary? boundary;
    void findBoundary(RenderObject obj) {
      if (obj is RenderRepaintBoundary && boundary == null) {
        boundary = obj;
        return;
      }
      obj.visitChildren(findBoundary);
    }
    findBoundary(renderObject);

    if (boundary == null) {
      debugPrint('   ⚠️ No RenderRepaintBoundary found, skipping');
      return;
    }

    final image = await boundary!.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      debugPrint('   ⚠️ Failed to encode image, skipping');
      return;
    }

    if (!screenshotDir.existsSync()) {
      screenshotDir.createSync(recursive: true);
    }
    final file = File('${screenshotDir.path}/$fileName.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    debugPrint('   Saved to ${file.path}');
  }

  // --- Auth/Setup bypass (same as massive_test.dart) ---
  Future<void> handleAuthAndSetup(WidgetTester tester) async {
    if (find.byKey(const Key('addBookButton')).evaluate().isNotEmpty) {
      return; // Already on Dashboard
    }

    // Skip onboarding
    if (find.byKey(const Key('onboardingSkipButton')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('onboardingSkipButton')));
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
    }

    // Run setup if needed
    if (find.byKey(const Key('setupNextButton')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('setupLibraryNameField')), 'Test Library');
      await tester.tap(find.byKey(const Key('setupProfileIndividual')));
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setupDemoNo')));
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setupNextButton')));
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

    // Login if needed
    if (find.byKey(const Key('loginButton')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('usernameField')), 'admin');
      await tester.enterText(
          find.byKey(const Key('passwordField')), 'admin');
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
  }

  // --- Navigation helper ---
  Future<void> navigateTo(WidgetTester tester, String route) async {
    // Find a widget inside the router tree (Scaffold is always present)
    final scaffoldFinder = find.byType(Scaffold);
    if (scaffoldFinder.evaluate().isEmpty) {
      debugPrint('⚠️ No Scaffold found, cannot navigate to $route');
      return;
    }
    final context = tester.element(scaffoldFinder.first);
    GoRouter.of(context).go(route);
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('Screenshot Tour', (WidgetTester tester) async {
    // Launch the app
    app.main();
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Handle auth/setup
    await handleAuthAndSetup(tester);
    await tester.pumpAndSettle();

    // ==========================================
    // 1. DASHBOARD
    // ==========================================
    await navigateTo(tester, '/dashboard');
    await takeScreenshot(tester, 'dashboard');

    // ==========================================
    // 2. STATISTICS
    // ==========================================
    await navigateTo(tester, '/statistics');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'statistics');

    // ==========================================
    // 3. BOOK LIST (grid view)
    // ==========================================
    await navigateTo(tester, '/books');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'book_list');

    // ==========================================
    // 4. SHELVES
    // ==========================================
    await navigateTo(tester, '/shelves');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'shelves');

    // ==========================================
    // 5. BOOK DETAILS — first book in list
    // ==========================================
    await navigateTo(tester, '/books');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final bookCards = find.byType(BookCoverCard);
    if (bookCards.evaluate().isNotEmpty) {
      await tester.tap(bookCards.first);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'book_details');
    }

    // ==========================================
    // 6. EDIT BOOK — from the first book
    // ==========================================
    // Tap "Modifier" button on book details screen
    final editButton = find.text('Modifier');
    if (editButton.evaluate().isNotEmpty) {
      await tester.tap(editButton.first);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'edit_book');
    }

    // ==========================================
    // 7. ADD BOOK SCREEN
    // ==========================================
    await navigateTo(tester, '/books/add');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'add_book');

    // ==========================================
    // 8. EXTERNAL SEARCH
    // ==========================================
    await navigateTo(tester, '/search/external');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'external_search');

    // ==========================================
    // 9. NETWORK / CONTACTS
    // ==========================================
    await navigateTo(tester, '/network');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'network_contacts');

    // ==========================================
    // 10. LOANS TAB (Prêts & Emprunts)
    // ==========================================
    final loansTab = find.text('Prêts & Emprunts');
    if (loansTab.evaluate().isNotEmpty) {
      await tester.tap(loansTab);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'network_loans');
    }

    // ==========================================
    // 11. PROFILE
    // ==========================================
    await navigateTo(tester, '/profile');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'profile');

    // ==========================================
    // 12. SETTINGS
    // ==========================================
    await navigateTo(tester, '/settings');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'settings');

    // ==========================================
    // 13. COLLECTIONS
    // ==========================================
    await navigateTo(tester, '/collections');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'collections');

    // ==========================================
    // 14. HELP
    // ==========================================
    await navigateTo(tester, '/help');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'help');

    // ==========================================
    // Done!
    // ==========================================
    debugPrint('🎉 Screenshot tour complete! $screenshotIndex screenshots saved.');
    debugPrint('📁 Location: ${screenshotDir.path}/');
  });
}
