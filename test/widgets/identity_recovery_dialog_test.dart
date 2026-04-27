import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/identity_recovery_dialog.dart';

/// Minimal i18n table covering every key the dialog reads in its success
/// states. Kept inline so the test is self-sufficient and survives
/// reorganization of the .po files.
const Map<String, String> _enKeys = {
  'identity_recovery_success_title': 'Done',
  'identity_recovery_success_body': 'Generic success body.',
  'identity_recovery_success_btn': 'OK',
  'identity_recovery_success_repair_title_one': '1 connection to re-pair',
  'identity_recovery_success_repair_title_other':
      '{count} connections to re-pair',
  'identity_recovery_success_repair_intro':
      'Re-pair each one from Network to restore secure actions.',
  'identity_recovery_success_btn_network': 'Go to Network',
  'identity_recovery_success_btn_later': 'Later',
  'identity_recovery_success_icon_device_label': 'Linked device',
  'identity_recovery_success_icon_peer_label': 'Peer library',
};

/// Pumps a tiny GoRouter shell with two routes (`/` and `/network`) and
/// returns the router so the test can inspect the active location after a
/// CTA tap. The dialog is built lazily by `dialogBuilder` so each test can
/// pass its own targets.
({GoRouter router, Widget app}) _buildHarness({
  required Widget Function(BuildContext context) dialogBuilder,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (innerContext) {
              // Launch the dialog as soon as the route is mounted so the
              // test does not need to drive a button tap before reaching
              // the success state.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showDialog<bool>(
                  context: innerContext,
                  barrierDismissible: false,
                  builder: dialogBuilder,
                );
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/network',
        builder: (context, state) =>
            const Scaffold(body: Text('NETWORK_SCREEN_MARKER')),
      ),
    ],
  );

  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );

  return (router: router, app: app);
}

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _enKeys});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets(
    'success state lists 2 targets and "Go to Network" navigates to /network',
    (tester) async {
      final harness = _buildHarness(
        dialogBuilder: (ctx) => IdentityRecoveryDialog(
          libraryUuid: 'test-uuid',
          debugInitialTargets: const [
            IdentityRepairTarget(label: 'iPhone de Federico', isDevice: true),
            IdentityRepairTarget(label: 'Bibliothèque Marie', isDevice: false),
          ],
        ),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // Title reflects the count via the plural key.
      expect(find.text('2 connections to re-pair'), findsOneWidget);
      // Both entries are rendered.
      expect(find.text('iPhone de Federico'), findsOneWidget);
      expect(find.text('Bibliothèque Marie'), findsOneWidget);
      // Both icon types are present (devices vs peer).
      expect(find.byIcon(Icons.devices), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);

      // Tap the primary CTA -> dialog dismisses and router navigates to
      // /network. The marker text confirms we landed on the right route.
      await tester.tap(find.text('Go to Network'));
      await tester.pumpAndSettle();

      expect(harness.router.routerDelegate.currentConfiguration.uri.path,
          '/network');
      expect(find.text('NETWORK_SCREEN_MARKER'), findsOneWidget);
      // Dialog itself is gone.
      expect(find.text('Go to Network'), findsNothing);
    },
  );

  testWidgets('singular form is used when there is exactly 1 target',
      (tester) async {
    final harness = _buildHarness(
      dialogBuilder: (ctx) => const IdentityRecoveryDialog(
        libraryUuid: 'test-uuid',
        debugInitialTargets: [
          IdentityRepairTarget(label: 'Solo device', isDevice: true),
        ],
      ),
    );

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(
      find.text('1 connection to re-pair'),
      findsOneWidget,
      reason: 'count == 1 must use the _one i18n key, not the plural template',
    );
  });

  testWidgets(
    'empty target list falls back to the generic OK-only success view',
    (tester) async {
      final harness = _buildHarness(
        dialogBuilder: (ctx) => const IdentityRecoveryDialog(
          libraryUuid: 'test-uuid',
          debugInitialTargets: [],
        ),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Generic success body.'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Go to Network'), findsNothing);
    },
  );
}
