import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/hub_registration_card.dart';

// ADR-073 D4: the settings row that says whether this device is registered
// on the hub, and withdraws the registration after a confirmation.

class _MockDeviceService extends DeviceService {}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  bool signedIn = false;
  String withdrawalAnswer = 'done';
  int withdrawals = 0;

  @override
  void setHubContactAllowed(bool allowed) {}

  @override
  Future<String> accountStatus() async => '{"signed_in": $signedIn}';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfigStrict() async => null;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfigStrict() async => null;

  @override
  Future<String> withdrawHubRegistration({
    String? nodeId,
    String? mailboxUuid,
  }) async {
    withdrawals++;
    return withdrawalAnswer;
  }
}

(HubDirectoryProvider, _MockFfiService) _hub({required bool registered}) {
  AuthService.storage = MockSecureStorage();
  final ffi = _MockFfiService();
  final hub = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    onlineServices: OnlineServicesConsent(
      readSignals: () async => NetworkUseSignals(hasPeer: registered),
    ),
  );
  return (hub, ffi);
}

Widget _harness(
  HubDirectoryProvider hub, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  // Providers above the MaterialApp, as in main.dart: a dialog route is
  // pushed on the root Navigator.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(child: HubRegistrationCard()),
      ),
    ),
  );
}

Future<String?> _storedChoice() async => (await SharedPreferences.getInstance())
    .getString(OnlineServicesConsent.prefKey);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // No catalogue loaded: every text renders as its key.
    TranslationService.setPoTranslationsForTest({});
    OnlineServicesConsent.debugAlwaysAllowed = false;
  });

  testWidgets('a device that is not registered is told so, with nothing to '
      'withdraw', (tester) async {
    final (hub, _) = _hub(registered: false);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    expect(find.text('hub_unreg_state_not_registered'), findsOneWidget);
    expect(find.text('hub_unreg_action'), findsNothing);
  });

  testWidgets('a registered device shows the way out', (tester) async {
    final (hub, _) = _hub(registered: true);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    expect(find.text('hub_unreg_state_registered'), findsOneWidget);
    expect(find.text('hub_unreg_action'), findsOneWidget);
  });

  testWidgets('the confirmation can be cancelled, and then nothing '
      'changes', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    expect(find.text('hub_unreg_confirm_title'), findsOneWidget);
    expect(find.text('hub_unreg_confirm_body'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(ffi.withdrawals, 0);
    expect(await _storedChoice(), isNull);
    expect(find.text('hub_unreg_state_registered'), findsOneWidget);
  });

  testWidgets('dismissing the confirmation is a cancel', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(ffi.withdrawals, 0);
    expect(await _storedChoice(), isNull);
  });

  testWidgets('confirming withdraws, and the row says the device is no '
      'longer registered', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hub_unreg_confirm_action'));
    await tester.pumpAndSettle();

    expect(ffi.withdrawals, 1);
    expect(await _storedChoice(), 'withdrawn');
    expect(find.text('hub_unreg_done'), findsOneWidget);
    expect(find.text('hub_unreg_state_not_registered'), findsOneWidget);
    expect(find.text('hub_unreg_action'), findsNothing);
  });

  testWidgets('a server that does not answer: the row says the deletion '
      'will be asked again', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    ffi.withdrawalAnswer = 'pending';
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hub_unreg_confirm_action'));
    await tester.pumpAndSettle();

    expect(find.text('hub_unreg_pending'), findsOneWidget);
    expect(find.text('hub_unreg_state_pending'), findsOneWidget);
    expect(find.text('hub_unreg_action'), findsNothing);
  });

  testWidgets('a server that refuses to confirm: the row says so and gives '
      'the page where a deletion can be asked for', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    ffi.withdrawalAnswer = 'unconfirmed';
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hub_unreg_confirm_action'));
    await tester.pumpAndSettle();

    expect(find.text('hub_unreg_unconfirmed'), findsOneWidget);
    expect(find.text('hub_unreg_state_unconfirmed'), findsOneWidget);
    expect(find.text('hub_unreg_action'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('online_reg_d_who_link'),
        matching: find.bySubtype<TextButton>(),
      ),
      findsOneWidget,
    );
  });

  testWidgets('signed in to an encrypted account: refused, with the way to '
      'the account', (tester) async {
    final (hub, ffi) = _hub(registered: true);
    ffi.signedIn = true;
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hub_unreg_action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hub_unreg_confirm_action'));
    await tester.pumpAndSettle();

    expect(ffi.withdrawals, 0);
    expect(await _storedChoice(), isNull);
    expect(find.text('hub_unreg_account_body'), findsOneWidget);
    expect(find.text('hub_unreg_account_action'), findsOneWidget);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.text('hub_unreg_state_registered'), findsOneWidget);
  });

  testWidgets('on a small phone at twice the text size nothing overflows, '
      'and both answers of the confirmation can be reached', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The real French text: the longest paragraph a reader meets here.
    final fr = File('assets/i18n/fr.po').readAsStringSync();
    final entries = RegExp(
      r'^msgid "(hub_unreg_[a-z_]+|cancel)"\nmsgstr "(.*)"$',
      multiLine: true,
    ).allMatches(fr);
    TranslationService.setPoTranslationsForTest({
      'en': {
        for (final m in entries) m.group(1)!: m.group(2)!.replaceAll(r'\n', '\n'),
      },
    });
    final (hub, _) = _hub(registered: true);
    await tester.pumpWidget(
      _harness(hub, textScaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Se désinscrire du serveur'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Annuler', 'Se désinscrire']) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
    }
  });

  testWidgets('the state is a live region and the button has a text '
      'label', (tester) async {
    final handle = tester.ensureSemantics();
    final (hub, _) = _hub(registered: true);
    await tester.pumpWidget(_harness(hub));
    await tester.pumpAndSettle();

    // The row merges its title and its state in one node: the state is
    // read with it, and announced again when it changes.
    final row = tester
        .getSemantics(find.text('hub_unreg_state_registered'))
        .getSemanticsData();
    expect(row.label, contains('hub_unreg_state_registered'));
    expect(row.flagsCollection.isLiveRegion, isTrue);
    expect(find.bySemanticsLabel('hub_unreg_action'), findsOneWidget);
    handle.dispose();
  });
}
