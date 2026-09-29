import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/flash_message_bar.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      const frb.FrbDirectoryConfig(
        nodeId: 'node-local',
        isListed: false,
        requiresApproval: true,
        acceptFrom: 'anyone',
        allowBorrowing: true,
      );
}

const _invite = 'To agree on a loan, Alice will need your contact details.';

/// The pairing banner is where a new peer first appears, so it is where the
/// missing contact card gets named: one extra line, inside the same live
/// region, with a button that opens the card form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeProvider theme;
  late FlashMessageProvider flashes;

  setUp(() {
    theme = ThemeProvider();
    flashes = FlashMessageProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'flash_peer_connected': 'Paired with',
        'flash_peer_pending': 'Connection request from',
        'flash_peer_browse': 'Browse',
        'flash_peer_review': 'Review',
        'flash_dismiss_tooltip': 'Dismiss',
        'flash_peer_contact_invite':
            'To agree on a loan, {name} will need your contact details.',
        'add': 'Add',
        'contact_prompt_action': 'Add my contact details',
        'contact_prompt_title': 'How can people reach you?',
        'hub_contact_email_label': 'Email',
        'done': 'Done',
      },
    });
  });

  Future<HubDirectoryProvider> hub({required String storedContact}) async {
    SharedPreferences.setMockInitialValues({'hub_contact_info': storedContact});
    final p = HubDirectoryProvider(ffi: _MockFfiService());
    await p.loadConfig();
    await p.loadContactInfo();
    return p;
  }

  Widget harness(HubDirectoryProvider hub) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: FlashMessageBar()),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<FlashMessageProvider>.value(value: flashes),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  void addPeer({required bool isPending}) => flashes.addEphemeralPeer(
    EphemeralPeerFlash(
      peerId: 7,
      peerName: 'Alice',
      nodeId: 'node-alice',
      connectedAt: DateTime(2026, 9, 29),
      isPending: isPending,
    ),
    showAccepted: true,
  );

  testWidgets('an accepted pairing with an empty card names the need', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final h = await hub(storedContact: '');
    addPeer(isPending: false);
    await tester.pumpWidget(harness(h));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_invite), findsOneWidget);
    // Read with the rest of the banner, not as a separate announcement.
    expect(
      find.ancestor(
        of: find.text(_invite),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Add my contact details'), findsOneWidget);
  });

  testWidgets('the button opens the contact card form', (tester) async {
    final h = await hub(storedContact: '');
    addPeer(isPending: false);
    await tester.pumpWidget(harness(h));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('How can people reach you?'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('a filled card leaves the banner as it was', (tester) async {
    final h = await hub(storedContact: 'Ask at the desk');
    addPeer(isPending: false);
    await tester.pumpWidget(harness(h));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paired with'), findsOneWidget);
    expect(find.text(_invite), findsNothing);
    expect(find.text('Add'), findsNothing);
  });

  testWidgets('a pending request carries no invitation', (tester) async {
    // Nothing is agreed yet: the request still has to be reviewed.
    final h = await hub(storedContact: '');
    addPeer(isPending: true);
    await tester.pumpWidget(harness(h));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connection request from'), findsOneWidget);
    expect(find.text(_invite), findsNothing);
  });

  testWidgets('accepting turns the pending banner into one, not two', (
    tester,
  ) async {
    final h = await hub(storedContact: '');
    addPeer(isPending: true);
    await tester.pumpWidget(harness(h));
    await tester.pumpAndSettle();

    addPeer(isPending: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('Connection request from'), findsNothing);
    expect(find.textContaining('Paired with'), findsOneWidget);
    expect(find.text(_invite), findsOneWidget);
  });
}
