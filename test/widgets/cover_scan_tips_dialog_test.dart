import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/cover_camera_helper.dart';
import 'package:bibliogenius/widgets/cover_scan_tips_dialog.dart';

/// The tips dialog shown before the cover scanner opens: skipped when the
/// scanner is not used or the user dismissed it for good, and Cancel must
/// stop the capture.
void main() {
  const tipsTitle = 'Cover photo';
  const dontShowAgain = "Don't show this message again";

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoverCameraHelper.debugScannerAvailableOverride = true;
    TranslationService.setPoTranslationsForTest({
      'en': {
        'cover_scan_tips_title': tipsTitle,
        'cover_scan_tips_ios': 'Tips (iOS)',
        'cover_scan_tips_android': 'Tips (Android)',
        'cover_scan_tips_dont_show_again': dontShowAgain,
        'cancel': 'Cancel',
        'continue': 'Continue',
      },
    });
  });

  tearDown(() {
    CoverCameraHelper.debugScannerAvailableOverride = null;
    TranslationService.setPoTranslationsForTest({});
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    late BuildContext screenContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                screenContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return screenContext;
  }

  Future<bool?> dismissedPref() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(CoverCameraHelper.scanTipsDismissedPrefKey);
  }

  testWidgets('continue opens the scanner without remembering anything', (
    tester,
  ) async {
    final screenContext = await pumpHost(tester);

    final result = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();
    expect(find.text(tipsTitle), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(await dismissedPref(), isNull);
  });

  testWidgets('cancel skips the capture', (tester) async {
    final screenContext = await pumpHost(tester);

    final result = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(await dismissedPref(), isNull);
  });

  testWidgets('"don\'t show again" hides the dialog on the next capture', (
    tester,
  ) async {
    final screenContext = await pumpHost(tester);

    final first = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();
    await tester.tap(find.text(dontShowAgain));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(await dismissedPref(), isTrue);

    final second = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();
    expect(find.text(tipsTitle), findsNothing);
    expect(await second, isTrue);
  });

  testWidgets('"don\'t show again" is kept even when cancelling', (
    tester,
  ) async {
    final screenContext = await pumpHost(tester);

    final result = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();
    await tester.tap(find.text(dontShowAgain));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(await dismissedPref(), isTrue);
  });

  testWidgets('no dialog when the plain camera is used', (tester) async {
    CoverCameraHelper.debugScannerAvailableOverride = false;
    final screenContext = await pumpHost(tester);

    final result = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();

    expect(find.text(tipsTitle), findsNothing);
    expect(await result, isTrue);
  });

  testWidgets('no dialog when auto crop is switched off', (tester) async {
    SharedPreferences.setMockInitialValues({
      CoverCameraHelper.autoCropPrefKey: false,
    });
    final screenContext = await pumpHost(tester);

    final result = showCoverScanTipsIfNeeded(screenContext);
    await tester.pumpAndSettle();

    expect(find.text(tipsTitle), findsNothing);
    expect(await result, isTrue);
  });

  test('switching auto crop back on brings the tips back', () async {
    SharedPreferences.setMockInitialValues({
      CoverCameraHelper.scanTipsDismissedPrefKey: true,
    });
    final themeProvider = ThemeProvider();

    await themeProvider.setCoverAutoCropEnabled(false);
    expect(await dismissedPref(), isTrue);

    await themeProvider.setCoverAutoCropEnabled(true);
    expect(await dismissedPref(), isNull);
  });
}
