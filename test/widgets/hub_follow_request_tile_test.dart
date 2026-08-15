import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/network_screen.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks (same shape as test/widgets/same_city_banner_test.dart, so a real
// provider can be built without bootstrapping FFI).
// ---------------------------------------------------------------------------

/// Generated library name, long enough that the pre-fix single-line row
/// truncated it on a phone.
const _longName = 'Bibliothèque de Mac Book Prof';

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.2.3';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// Pending requests handed back to the provider. Mutated by
  /// hubDirectoryResolveFollow so the reload after a resolution drains it.
  List<frb.FrbHubFollow> pending = [];

  /// (followId, resolution) of every resolution the UI triggered.
  final List<({int id, String resolution})> resolved = [];

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async => pending;

  @override
  Future<frb.FrbHubFollow?> hubDirectoryResolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
  }) async {
    resolved.add((id: followId, resolution: resolution));
    final target = pending.firstWhere((f) => f.id == followId);
    pending = pending.where((f) => f.id != followId).toList();
    return target;
  }

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => [];
}

frb.FrbHubFollow _follow({required int id, required String name}) {
  return frb.FrbHubFollow(
    id: id,
    followerNodeId: 'node-$id',
    followedNodeId: 'me',
    status: 'pending',
    createdAt: '2026-08-15T08:00:00Z',
    followerDisplayName: name,
  );
}

Future<HubDirectoryProvider> _provider(_MockFfiService ffi) async {
  SharedPreferences.setMockInitialValues({});
  AuthService.storage = MockSecureStorage();

  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await provider.loadPendingRequests();
  return provider;
}

Widget _tileHarness(HubDirectoryProvider hub, ThemeProvider theme) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
      ],
      child: Scaffold(
        // Narrow body: the truncation this widget fixes only shows up when
        // the card has phone-sized width, not the 800px test default.
        body: Center(
          child: SizedBox(
            width: 360,
            child: ListenableBuilder(
              listenable: hub,
              builder: (context, _) => hub.pendingRequests.isEmpty
                  ? const SizedBox.shrink()
                  : HubFollowRequestTile(
                      follow: hub.pendingRequests.first,
                      provider: hub,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Harness for the overflow sheet. Providers sit ABOVE the MaterialApp, as in
/// main.dart, because a modal route is pushed on the root Navigator and would
/// not see providers scoped inside `home`.
Widget _sheetHarness(HubDirectoryProvider hub, ThemeProvider theme) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHubFollowRequestsSheet(context, hub),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'directory_approve': 'Approve',
        'directory_reject': 'Reject',
        'directory_block': 'Block',
        'directory_wants_to_follow_you': 'Wants to follow you',
        'directory_requests_see_all': 'See all requests',
        'directory_requests_empty': 'No incoming follow requests.',
        'network_hub_requests_title': 'Follow requests',
        'more_actions': 'More',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  group('HubFollowRequestTile layout', () {
    testWidgets('renders the whole library name, not an ellipsized line', (
      tester,
    ) async {
      final ffi = _MockFfiService()..pending = [_follow(id: 1, name: _longName)];
      final hub = await _provider(ffi);

      await tester.pumpWidget(_tileHarness(hub, theme));
      await tester.pumpAndSettle();

      final nameText = tester.widget<Text>(find.text(_longName));
      expect(
        nameText.maxLines,
        2,
        reason:
            'Generated names run 25-35 characters. On one line next to the '
            'actions they were cut mid-word ("Bibliothèque de..."), which is '
            'the bug this card fixes.',
      );

      // Structural, not font-dependent: widget tests render in Ahem, whose
      // glyphs are square, so any character-count assertion would measure the
      // test font rather than the layout. What matters is how much width the
      // name is given. Three 48px icon buttons on the same line left it ~100
      // of 360 logical pixels; a full-width line gives it more than half.
      final nameWidth = tester.getRect(find.text(_longName)).width;
      final cardWidth = tester.getRect(find.byType(Card)).width;
      expect(
        nameWidth,
        greaterThan(cardWidth * 0.5),
        reason:
            'The name must own a full-width line instead of sharing it with '
            'the action buttons.',
      );
    });

    testWidgets('actions carry text labels, block is behind the overflow menu', (
      tester,
    ) async {
      final ffi = _MockFfiService()..pending = [_follow(id: 1, name: _longName)];
      final hub = await _provider(ffi);

      await tester.pumpWidget(_tileHarness(hub, theme));
      await tester.pumpAndSettle();

      // Labels, not colour-coded icons: tooltips never show on touch.
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Wants to follow you'), findsOneWidget);

      // Block is one deliberate tap away from approve, not adjacent to it.
      expect(find.text('Block'), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('approve resolves the request through the provider', (
      tester,
    ) async {
      final ffi = _MockFfiService()..pending = [_follow(id: 7, name: _longName)];
      final hub = await _provider(ffi);

      await tester.pumpWidget(_tileHarness(hub, theme));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(ffi.resolved, hasLength(1));
      expect(ffi.resolved.single.id, 7);
      expect(ffi.resolved.single.resolution, 'approve');
    });
  });

  group('Follow requests overflow sheet', () {
    testWidgets('lists every pending request, well past the inline preview', (
      tester,
    ) async {
      final ffi = _MockFfiService()
        ..pending = List.generate(
          7,
          (i) => _follow(id: i + 1, name: 'Library number ${i + 1}'),
        );
      final hub = await _provider(ffi);

      await tester.pumpWidget(_sheetHarness(hub, theme));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Follow requests (7)'), findsOneWidget);
      expect(find.text('Library number 1'), findsOneWidget);
      // Later entries are reachable by scrolling inside the sheet. The first
      // drag is partly absorbed by the draggable sheet expanding, so scroll
      // until the last card actually comes into view.
      await tester.scrollUntilVisible(
        find.text('Library number 7'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Library number 7'), findsOneWidget);
    });

    testWidgets('the sheet drains as requests are resolved', (tester) async {
      final ffi = _MockFfiService()
        ..pending = [
          _follow(id: 1, name: 'Library number 1'),
          _follow(id: 2, name: 'Library number 2'),
        ];
      final hub = await _provider(ffi);

      await tester.pumpWidget(_sheetHarness(hub, theme));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();

      expect(find.text('Follow requests (1)'), findsOneWidget);
      expect(find.text('Library number 1'), findsNothing);

      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();

      expect(find.text('No incoming follow requests.'), findsOneWidget);
    });
  });
}
