/// Shared auth/setup bypass for integration tests.
///
/// Lands the test on the Dashboard regardless of the entry state
/// (already logged in, onboarding tour visible, or login screen).
///
/// The setup wizard is bypassed at runtime in main.dart since the
/// `initializeDefaults()` change, so this helper does not handle it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> handleAuthAndSetup(WidgetTester tester) async {
  if (find.byKey(const Key('addBookButton')).evaluate().isNotEmpty) {
    return; // Already on Dashboard
  }

  // Skip onboarding tour if shown on first install
  if (find.byKey(const Key('onboardingSkipButton')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('onboardingSkipButton')));
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 1));
  }

  // Login if shown (admin/admin is the auto-provisioned account)
  if (find.byKey(const Key('loginButton')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('usernameField')), 'admin');
    await tester.enterText(find.byKey(const Key('passwordField')), 'admin');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }
}
