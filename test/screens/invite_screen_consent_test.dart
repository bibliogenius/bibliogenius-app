import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/invite_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/online_services_consent_dialog.dart';

// "Invite" is the first place where an installation that never shared
// anything meets the hub (ADR-073 D2): the question comes before the
// invitation screen, and a refusal leaves nothing behind.

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();
}

/// Counts what the invitation would have started on the hub.
class _RecordingHub extends HubDirectoryProvider {
  _RecordingHub({required bool usesNetwork})
    : super(
        ffi: _MockFfiService(),
        onlineServices: OnlineServicesConsent(
          readSignals: () async => NetworkUseSignals(hasAccount: usesNetwork),
        ),
      );

  /// Every call, and those made while the consent held.
  int startCalls = 0;
  int started = 0;

  @override
  Future<void> startOnlineServices({Duration? maxWait}) async {
    startCalls++;
    if (await this.onlineServicesAllowed()) started++;
  }
}

Future<_RecordingHub> _pump(
  WidgetTester tester, {
  bool usesNetwork = false,
}) async {
  SharedPreferences.setMockInitialValues({'languageCode': 'en'});
  AuthService.storage = MockSecureStorage();
  final hub = _RecordingHub(usesNetwork: usesNetwork);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
        ),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
        Provider<ApiService>.value(
          value: ApiService(AuthService(), baseUrl: 'http://localhost:0'),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInviteScreen(context),
              child: const Text('invite'),
            ),
          ),
        ),
      ),
    ),
  );
  return hub;
}

Future<String?> _storedChoice() async =>
    (await SharedPreferences.getInstance()).getString(
      OnlineServicesConsent.prefKey,
    );

void main() {
  setUp(() => TranslationService.setPoTranslationsForTest({}));

  testWidgets('refused: the invitation screen never opens and nothing is '
      'started on the hub', (tester) async {
    final hub = await _pump(tester);

    await tester.tap(find.text('invite'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineServicesConsentDialog), findsOneWidget);
    expect(find.byType(InviteScreen), findsNothing);

    await tester.tap(find.text('online_reg_refuse'));
    await tester.pumpAndSettle();

    expect(find.byType(InviteScreen), findsNothing);
    expect(hub.startCalls, 0, reason: 'the screen behind the dialog never ran');
    expect(await _storedChoice(), isNull);
  });

  testWidgets('accepted: the invitation screen opens and the hub calls '
      'start', (tester) async {
    final hub = await _pump(tester);

    await tester.tap(find.text('invite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('online_reg_accept'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(InviteScreen), findsOneWidget);
    expect(hub.started, 1);
    expect(await _storedChoice(), 'granted');
  });

  testWidgets('an installation that already consents goes straight to its '
      'invitation', (tester) async {
    final hub = await _pump(tester, usesNetwork: true);

    await tester.tap(find.text('invite'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(OnlineServicesConsentDialog), findsNothing);
    expect(find.byType(InviteScreen), findsOneWidget);
    expect(hub.started, 1);
  });
}
