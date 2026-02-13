/// Network Contacts — 10 Personas Integration Test with Screenshots
///
/// Tests the Contacts tab of the NetworkScreen with 10 different user personas,
/// each validating specific UX scenarios. Captures ~20 screenshots for visual review.
///
/// Run with:
///   flutter test integration_test/network_contacts_test.dart -d macos
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
import 'package:provider/provider.dart';

import 'package:bibliogenius/main.dart' as app;
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/api_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Use mock storage to avoid Keychain prompts
  AuthService.storage = MockSecureStorage();

  // Suppress expected image load errors and overflow
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

  // Clean previous network screenshots on start
  if (screenshotDir.existsSync()) {
    for (final file in screenshotDir.listSync()) {
      if (file is File && file.path.contains('network_') && file.path.endsWith('.png')) {
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
    debugPrint('   ✅ Saved to ${file.path}');
  }

  // --- Auth/Setup bypass (same as screenshot_tour.dart) ---
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
        find.byKey(const Key('setupLibraryNameField')),
        'Test Library',
      );
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
        find.byKey(const Key('passwordField')),
        'admin',
      );
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
  }

  // --- Navigation helper ---
  Future<void> navigateTo(WidgetTester tester, String route) async {
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

  // --- Helper: create a test contact via API ---
  Future<void> createTestContact(
    WidgetTester tester,
    String name, {
    String? firstName,
    String? email,
    String type = 'borrower',
  }) async {
    final scaffoldFinder = find.byType(Scaffold);
    if (scaffoldFinder.evaluate().isEmpty) return;
    final context = tester.element(scaffoldFinder.first);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.createContact({
        'name': name,
        'first_name': firstName,
        'email': email,
        'type': type,
        'library_owner_id': 1,
        'is_active': true,
      });
      debugPrint('   ✅ Created contact: $name');
    } catch (e) {
      debugPrint('   ⚠️ Failed to create contact $name: $e');
    }
  }

  // --- Helper: delete all test contacts ---
  Future<void> cleanupTestContacts(WidgetTester tester) async {
    final scaffoldFinder = find.byType(Scaffold);
    if (scaffoldFinder.evaluate().isEmpty) return;
    final context = tester.element(scaffoldFinder.first);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final response = await api.getContacts();
      final contacts = (response.data['data'] ?? response.data) as List;
      for (final contact in contacts) {
        final id = contact['id'] as int?;
        final name = contact['name'] as String? ?? '';
        // Only delete our test contacts (prefixed with test names)
        if (id != null &&
            (name.startsWith('TestContact_') || name.startsWith('Persona_'))) {
          try {
            await api.deleteContact(id);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('   ⚠️ Cleanup failed: $e');
    }
  }

  // =========================================================================
  // MAIN TEST: Network Contacts — 10 Personas Tour
  // =========================================================================
  testWidgets('Network Contacts — Persona Tour', (WidgetTester tester) async {
    // Launch the app
    app.main();
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Handle auth/setup
    await handleAuthAndSetup(tester);
    await tester.pumpAndSettle();

    // Clean up any leftover test contacts
    await cleanupTestContacts(tester);

    // =====================================================================
    // PERSONA 1: Alice — New user (empty state)
    // =====================================================================
    debugPrint('\n👤 Persona 1: Alice — New user (empty state)');

    await navigateTo(tester, '/network');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Screenshot: Contacts tab active
    await takeScreenshot(tester, 'network_contacts_tab_active');

    // Verify empty state is visible (only if no contacts exist)
    final emptyState = find.byKey(const Key('networkEmptyState'));
    if (emptyState.evaluate().isNotEmpty) {
      debugPrint('   ✅ Empty state visible');
      await takeScreenshot(tester, 'network_alice_empty_state');

      // Verify empty state CTA exists
      expect(find.byKey(const Key('addFirstContactBtn')), findsOneWidget);
    } else {
      debugPrint('   ℹ️ Not empty (existing contacts found), skipping empty state screenshot');
    }

    // Test FAB → Bottom Sheet
    final fab = find.byKey(const Key('networkAddFab'));
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // Verify bottom sheet items
    expect(find.byKey(const Key('actionEnterManually')), findsOneWidget);
    expect(find.byKey(const Key('actionScanQr')), findsOneWidget);
    expect(find.byKey(const Key('actionShowMyCode')), findsOneWidget);

    await takeScreenshot(tester, 'network_alice_fab_bottom_sheet');

    // Close bottom sheet
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Test QR Help dialog (from empty state, if visible)
    if (emptyState.evaluate().isNotEmpty) {
      final qrHelpBtn = find.textContaining('QR Code');
      if (qrHelpBtn.evaluate().isNotEmpty) {
        await tester.tap(qrHelpBtn.first);
        await tester.pumpAndSettle();
        final helpDialog = find.byKey(const Key('qrHelpDialog'));
        if (helpDialog.evaluate().isNotEmpty) {
          await takeScreenshot(tester, 'network_alice_qr_help_dialog');
          // Close dialog
          final understoodBtn = find.text('Understood');
          final comprisBtn = find.text('Compris');
          if (understoodBtn.evaluate().isNotEmpty) {
            await tester.tap(understoodBtn);
          } else if (comprisBtn.evaluate().isNotEmpty) {
            await tester.tap(comprisBtn);
          }
          await tester.pumpAndSettle();
        }
      }

      // Test Show Code Help dialog
      // This button is from the empty state text button
      final showCodeTextBtn = find.textContaining('code');
      if (showCodeTextBtn.evaluate().length > 1) {
        // The second "code" mention is likely the "How to show my code" button
        await tester.tap(showCodeTextBtn.last);
        await tester.pumpAndSettle();
        final codeHelpDialog = find.byKey(const Key('showCodeHelpDialog'));
        if (codeHelpDialog.evaluate().isNotEmpty) {
          await takeScreenshot(tester, 'network_alice_show_code_help_dialog');
          // Close
          final understoodBtn = find.text('Understood');
          final comprisBtn = find.text('Compris');
          if (understoodBtn.evaluate().isNotEmpty) {
            await tester.tap(understoodBtn);
          } else if (comprisBtn.evaluate().isNotEmpty) {
            await tester.tap(comprisBtn);
          }
          await tester.pumpAndSettle();
        }
      }
    }

    // =====================================================================
    // PERSONA 2: Bob — 5 borrower contacts, no peers
    // =====================================================================
    debugPrint('\n👤 Persona 2: Bob — Bibliophile solo (5 contacts)');

    // Create 5 test contacts
    for (int i = 1; i <= 5; i++) {
      await createTestContact(
        tester,
        'Persona_Bob_$i',
        firstName: 'Borrower$i',
        email: 'bob$i@test.com',
      );
    }

    // Reload the page
    await navigateTo(tester, '/network');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await takeScreenshot(tester, 'network_bob_contacts_list');

    // Test filter: Borrowers
    final filterBorrowers = find.byKey(const Key('filterBorrowers'));
    if (filterBorrowers.evaluate().isNotEmpty) {
      await tester.tap(filterBorrowers);
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'network_bob_filter_borrowers');
    }

    // Reset filter to All
    final filterAll = find.byKey(const Key('filterAll'));
    if (filterAll.evaluate().isNotEmpty) {
      await tester.tap(filterAll);
      await tester.pumpAndSettle();
    }

    // =====================================================================
    // PERSONA 3: Claire — Mixed contacts + peers (if P2P enabled)
    // =====================================================================
    debugPrint('\n👤 Persona 3: Claire — Networkeuse active (mixed list)');

    await navigateTo(tester, '/network');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await takeScreenshot(tester, 'network_claire_mixed_list');

    // Test filter: Libraries
    final filterLibraries = find.byKey(const Key('filterLibraries'));
    if (filterLibraries.evaluate().isNotEmpty) {
      await tester.tap(filterLibraries);
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'network_claire_filter_libraries');

      // Reset
      await tester.tap(filterAll);
      await tester.pumpAndSettle();
    }

    // =====================================================================
    // PERSONA 4: David — mDNS discovery
    // =====================================================================
    debugPrint('\n👤 Persona 4: David — mDNS discovery');

    // Check if local network section is visible
    final localSection = find.byKey(const Key('localNetworkSection'));
    if (localSection.evaluate().isNotEmpty) {
      debugPrint('   ✅ Local network section found');
      await tester.ensureVisible(localSection);
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'network_david_local_network_section');
    } else {
      debugPrint('   ℹ️ No mDNS peers discovered (expected in CI)');
    }

    // =====================================================================
    // PERSONA 5: Eva — Peer with pending status
    // =====================================================================
    debugPrint('\n👤 Persona 5: Eva — Pending peer');

    // Look for any pending status badges
    final pendingBadge = find.text('Pending approval');
    final pendingBadgeFr = find.text("En attente d'approbation");
    if (pendingBadge.evaluate().isNotEmpty ||
        pendingBadgeFr.evaluate().isNotEmpty) {
      debugPrint('   ✅ Pending peer badge found');
      await takeScreenshot(tester, 'network_eva_pending_peer');
    } else {
      debugPrint('   ℹ️ No pending peers (expected without P2P connections)');
    }

    // =====================================================================
    // PERSONA 6: François — Offline peer
    // =====================================================================
    debugPrint('\n👤 Persona 6: François — Offline peer');

    final offlineBadge = find.text('Offline');
    final offlineBadgeFr = find.text('Hors ligne');
    if (offlineBadge.evaluate().isNotEmpty ||
        offlineBadgeFr.evaluate().isNotEmpty) {
      debugPrint('   ✅ Offline peer badge found');
      await takeScreenshot(tester, 'network_francois_offline_peer');
    } else {
      debugPrint('   ℹ️ No offline peers (expected without P2P connections)');
    }

    // =====================================================================
    // PERSONA 7: Gina — Show My QR Code
    // =====================================================================
    debugPrint('\n👤 Persona 7: Gina — Show My QR Code');

    // Open FAB → Show My Code
    await tester.tap(find.byKey(const Key('networkAddFab')));
    await tester.pumpAndSettle();

    final showMyCodeAction = find.byKey(const Key('actionShowMyCode'));
    expect(showMyCodeAction, findsOneWidget);
    await tester.tap(showMyCodeAction);
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify dialog appeared
    final showMyCodeDialog = find.byKey(const Key('showMyCodeDialog'));
    if (showMyCodeDialog.evaluate().isNotEmpty) {
      debugPrint('   ✅ Show My Code dialog visible');

      // Check if QR code is visible or WiFi error
      final qrImage = find.byKey(const Key('myQrCode'));
      if (qrImage.evaluate().isNotEmpty) {
        debugPrint('   ✅ QR code generated');
      } else {
        debugPrint('   ℹ️ QR code not generated (no WiFi or IP)');
      }

      await takeScreenshot(tester, 'network_gina_show_my_qr_code');

      // Close dialog
      final closeBtn = find.text('Close');
      final closeBtnFr = find.text('Fermer');
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn);
      } else if (closeBtnFr.evaluate().isNotEmpty) {
        await tester.tap(closeBtnFr);
      }
      await tester.pumpAndSettle();
    }

    // =====================================================================
    // PERSONA 8: Hugo — Delete contact + peer
    // =====================================================================
    debugPrint('\n👤 Persona 8: Hugo — Delete contact');

    await navigateTo(tester, '/network');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Find any delete icon (delete_outline) on a member tile
    final deleteIcons = find.byIcon(Icons.delete_outline);
    if (deleteIcons.evaluate().isNotEmpty) {
      debugPrint('   ✅ Found ${deleteIcons.evaluate().length} delete buttons');

      // Tap the first delete button
      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();

      // Verify confirmation dialog appeared
      final confirmDialog = find.byType(AlertDialog);
      if (confirmDialog.evaluate().isNotEmpty) {
        await takeScreenshot(tester, 'network_hugo_delete_contact_confirm');

        // Cancel the deletion (don't actually delete)
        final cancelBtn = find.text('Cancel');
        final cancelBtnFr = find.text('Annuler');
        if (cancelBtn.evaluate().isNotEmpty) {
          await tester.tap(cancelBtn);
        } else if (cancelBtnFr.evaluate().isNotEmpty) {
          await tester.tap(cancelBtnFr);
        }
        await tester.pumpAndSettle();
      }
    } else {
      debugPrint('   ℹ️ No delete buttons found');
    }

    // =====================================================================
    // PERSONA 9: Iris — Narrow screen (< 600px)
    // =====================================================================
    debugPrint('\n👤 Persona 9: Iris — Responsive narrow (< 600px)');

    // Resize window to narrow
    await binding.setSurfaceSize(const Size(500, 800));
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await takeScreenshot(tester, 'network_iris_narrow_layout');

    // =====================================================================
    // PERSONA 10: Jean — Wide screen (> 600px)
    // =====================================================================
    debugPrint('\n👤 Persona 10: Jean — Responsive wide (> 900px)');

    // Resize window to wide
    await binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await takeScreenshot(tester, 'network_jean_wide_layout');

    // Reset to default size
    await binding.setSurfaceSize(null);
    await tester.pumpAndSettle();

    // =====================================================================
    // BONUS: Loans tab screenshot
    // =====================================================================
    debugPrint('\n📋 Bonus: Loans tab');

    await navigateTo(tester, '/network');
    await tester.pumpAndSettle();

    // Find and tap the Loans tab
    final loansTab = find.text('Loans & Borrowing');
    final loansTabFr = find.text('Prêts & Emprunts');
    if (loansTab.evaluate().isNotEmpty) {
      await tester.tap(loansTab);
    } else if (loansTabFr.evaluate().isNotEmpty) {
      await tester.tap(loansTabFr);
    }
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'network_loans_tab');

    // =====================================================================
    // BONUS: Add contact form (navigate to /contacts/add)
    // =====================================================================
    debugPrint('\n📋 Bonus: Add contact form');

    await navigateTo(tester, '/contacts/add');
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await takeScreenshot(tester, 'network_add_contact_form');

    // =====================================================================
    // BONUS: Contextual help
    // =====================================================================
    debugPrint('\n📋 Bonus: Contextual help');

    await navigateTo(tester, '/network');
    await tester.pumpAndSettle();

    // Find the help icon button in the app bar
    final helpIcon = find.byIcon(Icons.help_outline);
    if (helpIcon.evaluate().isNotEmpty) {
      await tester.tap(helpIcon.first);
      await tester.pumpAndSettle();
      await takeScreenshot(tester, 'network_contextual_help');

      // Close help sheet
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // =====================================================================
    // CLEANUP
    // =====================================================================
    debugPrint('\n🧹 Cleaning up test contacts...');
    await cleanupTestContacts(tester);

    // =====================================================================
    // DONE
    // =====================================================================
    debugPrint('\n🎉 Network Contacts persona tour complete!');
    debugPrint('   📸 $screenshotIndex screenshots saved to ${screenshotDir.path}/');
  });
}
