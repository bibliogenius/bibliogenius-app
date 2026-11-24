import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/hub_directory.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/discover_card.dart';
import 'package:bibliogenius/widgets/invite_share_direct.dart';
import 'package:bibliogenius/widgets/online_services_consent_dialog.dart';

// Network gestures on an installation that never chose the online services
// (ADR-073 D2): the question comes first, and a refusal sends nothing.

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test';

  @override
  Future<String?> getAppVersion() async => '1.4.2';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  int followCalls = 0;

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async {
    followCalls++;
    return frb.FrbHubFollow(
      id: 1,
      followerNodeId: 'me',
      followedNodeId: nodeId,
      status: 'pending',
      createdAt: '2026-11-24T00:00:00Z',
    );
  }

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async => const [];

  // What the registration behind a first follow needs.
  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => null;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => null;

  @override
  Future<int> countBooks() async => 3;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async => frb.FrbDirectoryConfig(
    nodeId: params.nodeId,
    isListed: false,
    requiresApproval: true,
    acceptFrom: params.acceptFrom,
    allowBorrowing: false,
  );
}

/// A hub whose calls are counted instead of made.
class _Hub extends HubDirectoryProvider {
  _Hub(this.mockFfi)
    : super(
        ffi: mockFfi,
        deviceService: _MockDeviceService(),
        onlineServices: OnlineServicesConsent(
          readSignals: () async => const NetworkUseSignals(),
        ),
      );

  final _MockFfiService mockFfi;
  int startCalls = 0;

  @override
  Future<void> startOnlineServices({Duration? maxWait}) async => startCalls++;

}

Widget _harness(_Hub hub, Widget Function(BuildContext) child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
    Provider<ApiService>.value(
      value: ApiService(AuthService(), baseUrl: 'http://localhost:0'),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 360, child: Builder(builder: child)),
      ),
    ),
  ),
);

Future<String?> _storedChoice() async =>
    (await SharedPreferences.getInstance()).getString(
      OnlineServicesConsent.prefKey,
    );

void main() {
  late _Hub hub;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthService.storage = MockSecureStorage();
    // Short labels for the card, as in its own test; the dialog renders
    // its keys.
    TranslationService.setPoTranslationsForTest({
      'en': {
        'directory_request': 'Request',
        'directory_follow': 'Follow',
        'directory_pending': 'Awaiting',
        'directory_following': 'Following',
        'directory_books': 'books',
      },
    });
    hub = _Hub(_MockFfiService());
  });

  group('following a library from its directory card', () {
    Widget card(BuildContext _) => const DiscoverCard(
      profile: HubProfile(
        nodeId: 'node-1',
        displayName: 'A library',
        bookCount: 12,
        locationCountry: 'FR',
        requiresApproval: true,
      ),
    );

    testWidgets('refused: no follow request leaves', (tester) async {
      await tester.pumpWidget(_harness(hub, card));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineServicesConsentDialog), findsOneWidget);
      await tester.tap(find.text('online_reg_refuse'));
      await tester.pumpAndSettle();

      expect(hub.mockFfi.followCalls, 0);
      expect(hub.startCalls, 0);
      expect(await _storedChoice(), isNull);
    });

    testWidgets('accepted: the follow request is sent', (tester) async {
      await tester.pumpWidget(_harness(hub, card));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('online_reg_accept'));
      await tester.pumpAndSettle();

      expect(hub.mockFfi.followCalls, 1);
      expect(await _storedChoice(), 'granted');
    });
  });

  group('sharing the invite link in one tap', () {
    Widget button(BuildContext context) => TextButton(
      onPressed: () => shareInviteLinkDirect(context),
      child: const Text('share'),
    );

    testWidgets('refused: no link is prepared and nothing starts on the hub', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(hub, button));

      await tester.tap(find.text('share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('online_reg_refuse'));
      await tester.pumpAndSettle();

      expect(hub.startCalls, 0);
      // The "preparing your link" notice never showed.
      expect(find.text('generating_invite_link'), findsNothing);
      expect(await _storedChoice(), isNull);
    });

    testWidgets('accepted: the hub calls start', (tester) async {
      await tester.pumpWidget(_harness(hub, button));

      await tester.tap(find.text('share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('online_reg_accept'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Once for the link, and again by the invitation screen it falls
      // back on when the link cannot be built (no local server here).
      expect(hub.startCalls, greaterThan(0));
      expect(await _storedChoice(), 'granted');
    });
  });
}
