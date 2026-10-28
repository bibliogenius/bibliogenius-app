// Pins what the settings page does today, before it is split into one file
// per section and then reorganised. Each test names a behaviour the reader
// relies on, not a layout: these must pass unchanged on the single screen and
// on the split one.
//
// - A quick preset confirms itself with the `preset_applied` SnackBar, also on
//   a first launch (no saved preference at all).
// - A parent toggle reveals its children (Games -> Memory game).
// - Each `/settings?focus=` deep link (dashboard tiles, help topics) opens the
//   sheet it targets.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/audio/providers/audio_provider.dart';
import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/settings_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';

import '../helpers/mock_classes.dart';

/// The library config the page loads on open, answered empty.
class _OfflineApiService extends MockApiService {
  @override
  Future<Response> getLibraryConfig() async => Response(
    requestOptions: RequestOptions(path: '/api/config'),
    statusCode: 200,
    data: <String, dynamic>{},
  );
}

/// The hub directory of a reader who never joined it.
class _OfflineHubDirectoryProvider extends HubDirectoryProvider {
  _OfflineHubDirectoryProvider() : super(ffi: FfiService());

  @override
  Future<void> loadConfig() async {}

  @override
  Future<bool> ensureRegistered() async => false;

  @override
  Future<void> loadFollowing() async {}

  @override
  Future<void> loadPendingRequests() async {}
}

/// The page loads in full, with no relay configured yet, and Connect waits
/// on [setupReply] so a test can act while the hub has not answered.
class _RelayApiService extends _OfflineApiService {
  final setupReply = Completer<Response>();
  int setupCalls = 0;

  Response _empty(String path) => Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: <String, dynamic>{},
  );

  @override
  Future<Response> getMe() async => _empty('/api/me');

  @override
  Future<Response> getUserStatus() async => _empty('/api/user/status');

  // No relay yet. Throwing (not answering "none") also keeps the page from
  // auto-connecting on load, which would use up [setupReply].
  @override
  Future<Response> getRelayConfig() async => throw StateError('no relay');

  @override
  Future<Response> setupRelay({required String relayUrl}) {
    setupCalls++;
    return setupReply.future;
  }
}

class _RecordingHubDirectoryProvider extends _OfflineHubDirectoryProvider {
  int relayPublished = 0;

  @override
  Future<void> ensureRelayPublished() async => relayPublished++;
}

/// Mounts the settings page at [location] and returns its theme provider.
Future<ThemeProvider> _pumpSettings(
  WidgetTester tester, {
  String location = '/settings',
  ApiService? api,
  HubDirectoryProvider? hub,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // The test font draws every glyph as a full square, so rows sized for real
  // text can overflow here and nowhere else.
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);

  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
  await tester.runAsync(theme.loadSettings);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, state) =>
            SettingsScreen(initialFocus: state.uri.queryParameters['focus']),
      ),
    ],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        Provider<ApiService>.value(value: api ?? _OfflineApiService()),
        Provider<AuthService>.value(value: MockAuthService()),
        ChangeNotifierProvider<HubDirectoryProvider>(
          create: (_) => hub ?? _OfflineHubDirectoryProvider(),
        ),
        ChangeNotifierProvider<OwnershipPreferenceProvider>(
          create: (_) => OwnershipPreferenceProvider(),
        ),
        ChangeNotifierProvider<AudioProvider>(create: (_) => AudioProvider()),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider<FlashMessageProvider>(
          create: (_) => FlashMessageProvider(),
        ),
        ChangeNotifierProvider<BackupSchedulerService>(
          create: (_) => BackupSchedulerService(
            prefs: prefs,
            authService: MockAuthService(),
            clock: DateTime.now,
            probeWatermark: () async => null,
            runBackup: (_) async =>
                const BackupRunResult(archivePath: '', archiveSizeBytes: 0),
            resolveBackupsDir: () async => Directory.systemTemp,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return theme;
}

/// Settles without `pumpAndSettle`: sections wait on futures that never
/// complete with the FFI down.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// [key] in the language the page renders, so a reworded label in the .po
/// files does not break the test.
String _t(WidgetTester tester, String key) => TranslationService.translate(
  tester.element(find.byType(SettingsScreen)),
  key,
);

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

void main() {
  setUpAll(() async {
    // `ApiService.hubUrl` reads the env; the page renders it.
    dotenv.testLoad();
    // The peer covers card sizes its disk cache under the temp directory.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    await TranslationService.loadTranslations();
  });

  setUp(() {
    // A first launch: nothing saved yet, not even a language.
    SharedPreferences.setMockInitialValues({});
    // The Reader preset seeds the favorites collection through the FFI,
    // which is not up under test.
    ThemeProvider.seedFavoritesOverride = () async => true;
  });

  tearDown(() => ThemeProvider.seedFavoritesOverride = null);

  group('quick presets', () {
    for (final (preset, labelKey) in [
      ('reader', 'preset_reader'),
      ('librarian', 'preset_librarian'),
      ('bookseller', 'preset_bookseller'),
    ]) {
      testWidgets('the $preset preset confirms itself on a first launch', (
        tester,
      ) async {
        await _pumpSettings(tester);
        final label = _t(tester, labelKey);

        // The preset setters push the module list to a server that is not
        // there: let their real futures run out.
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('${_t(tester, 'preset_applied')}: $label'),
          ),
          findsOneWidget,
        );
      });
    }
  });

  testWidgets('turning Games on reveals the Memory game toggle', (
    tester,
  ) async {
    // Games are on by default: start from a reader who turned them off.
    SharedPreferences.setMockInitialValues({'gamesEnabled': false});
    await _pumpSettings(tester);
    final modules = find.text(_t(tester, 'modules'));
    await tester.ensureVisible(modules);
    await tester.tap(modules);
    await _settle(tester);

    final memoryGame = find.text(_t(tester, 'memory_game_module'));
    expect(memoryGame, findsNothing);

    final games = find.ancestor(
      of: find.text(_t(tester, 'games_module')),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(games);
    await tester.runAsync(() async {
      await tester.tap(games);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await _settle(tester);

    expect(memoryGame, findsOneWidget);
  });

  testWidgets('a search opens the matching section and hides the others', (
    tester,
  ) async {
    await _pumpSettings(tester);
    final memoryGame = find.text(_t(tester, 'memory_game_module'));
    final springboard = find.text(_t(tester, 'settings_springboard_title'));
    final theme = find.text(_t(tester, 'theme_title'));
    expect(memoryGame, findsNothing);
    expect(springboard, findsOneWidget);
    expect(theme, findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'memory');
    await _settle(tester);

    // The Modules section opens on its own, without a tap.
    await tester.ensureVisible(memoryGame);
    expect(memoryGame, findsOneWidget);
    expect(springboard, findsNothing);
    expect(theme, findsNothing);
  });

  testWidgets('a relay connection completes with the Network section closed', (
    tester,
  ) async {
    final api = _RelayApiService();
    final hub = _RecordingHubDirectoryProvider();
    await _pumpSettings(tester, api: api, hub: hub);

    final network = find.text(_t(tester, 'settings_network_title'));
    final details = find.text(_t(tester, 'settings_remote_reachable_details'));
    Future<void> openRelayDetails() async {
      await tester.ensureVisible(network);
      await tester.tap(network);
      await _settle(tester);
      await tester.ensureVisible(details);
      await tester.tap(details);
      await _settle(tester);
    }

    await openRelayDetails();
    final connect = find.text(_t(tester, 'relay_connect'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pump();
    expect(api.setupCalls, 1);

    // Close Network before the hub answers.
    await tester.ensureVisible(network);
    await tester.tap(network);
    await _settle(tester);
    expect(connect, findsNothing);

    api.setupReply.complete(
      Response(
        requestOptions: RequestOptions(path: '/api/relay/setup'),
        statusCode: 200,
        data: {'mailbox_uuid': '0123456789abcdef'},
      ),
    );
    await _settle(tester);
    expect(hub.relayPublished, 1);

    await openRelayDetails();
    expect(find.text(_t(tester, 'relay_disconnect')), findsOneWidget);
    expect(find.text('Mailbox: 01234567...'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  group('focus deep links', () {
    testWidgets('no focus opens no sheet', (tester) async {
      await _pumpSettings(tester);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('focus=wifi opens the local Wi-Fi sharing sheet', (
      tester,
    ) async {
      await _pumpSettings(tester, location: '/settings?focus=wifi');
      expect(
        _inSheet(find.text(_t(tester, 'settings_goal_local_wifi'))),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text(_t(tester, 'settings_network_discovery'))),
        findsOneWidget,
      );
    });

    testWidgets('focus=public opens the public directory sheet', (
      tester,
    ) async {
      await _pumpSettings(tester, location: '/settings?focus=public');
      expect(
        _inSheet(find.text(_t(tester, 'directory_settings_title'))),
        findsOneWidget,
      );
    });

    testWidgets('focus=backup opens the backup sheet', (tester) async {
      await _pumpSettings(tester, location: '/settings?focus=backup');
      expect(
        _inSheet(find.text(_t(tester, 'settings_goal_backup'))),
        findsOneWidget,
      );
    });

    testWidgets('focus=language opens the reading languages sheet', (
      tester,
    ) async {
      await _pumpSettings(tester, location: '/settings?focus=language');
      expect(
        _inSheet(find.text(_t(tester, 'settings_goal_language'))),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text(_t(tester, 'languages_reading'))),
        findsOneWidget,
      );
    });
  });
}
