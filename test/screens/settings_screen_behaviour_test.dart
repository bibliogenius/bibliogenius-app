// Pins what the settings page does. Each test names a behaviour the reader
// relies on, not a layout. They were written before the page was split into
// one file per section and passed unchanged on both; the reorganisation only
// changed where the presets sit (now inside Features), and the section pages
// only how a section opens (a page instead of an accordion).
//
// - A quick preset confirms itself with the `preset_applied` SnackBar, also on
//   a first launch (no saved preference at all).
// - A parent toggle reveals its children (Games -> Memory game).
// - Each `/settings?focus=` deep link (dashboard tiles, help topics) opens the
//   sheet it targets.
// - Each setting has a single place, and a search finds it there.
// - Each section has its own page; a search result's title opens it.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/audio/providers/audio_provider.dart';
import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/settings/settings_scope.dart';
import 'package:bibliogenius/screens/settings/settings_section_screen.dart';
import 'package:bibliogenius/screens/settings/settings_sections.dart';
import 'package:bibliogenius/screens/settings_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/goal_tile.dart';

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

/// A backend whose stored search settings a test changes between visits.
class _StoredSearchApiService extends _OfflineApiService {
  String googleKey = '';
  Map<String, bool> sources = {};

  Response _reply(String path, Object data) => Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: data,
  );

  @override
  Future<Response> getMe() async => _reply('/api/me', <String, dynamic>{});

  @override
  Future<Response> getUserStatus() async => _reply('/api/user/status', {
    'config': {
      'fallback_preferences': {...sources},
      'api_keys': {if (googleKey.isNotEmpty) 'google_books': googleKey},
    },
  });

  @override
  Future<Response> getRelayConfig() async =>
      _reply('/api/relay', <String, dynamic>{});

  @override
  Future<Response> updateProfile({required Map<String, dynamic> data}) async =>
      _reply('/api/profile', <String, dynamic>{});
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
        routes: [settingsSectionRoute],
      ),
      GoRoute(
        path: '/elsewhere',
        builder: (_, _) => const Scaffold(body: Text('elsewhere')),
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
        ChangeNotifierProvider<SettingsData>(create: (_) => SettingsData()),
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
/// files does not break the test. Read from the navigator, which stays
/// onstage when a section page covers the list.
String _t(WidgetTester tester, String key) => TranslationService.translate(
  tester.element(find.byType(Navigator).first),
  key,
);

/// Opens the page of the section titled [titleKey] from the section list.
Future<void> _openSection(WidgetTester tester, String titleKey) async {
  final entry = find.widgetWithText(ListTile, _t(tester, titleKey));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await _settle(tester);
}

/// Leaves a section page for the section list.
Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_t(tester, 'back')));
  await _settle(tester);
}

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
        await _openSection(tester, 'modules');
        final label = _t(tester, labelKey);
        await tester.ensureVisible(find.text(label));

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
    await _openSection(tester, 'modules');

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

  testWidgets('a relay connection completes with the Network page closed', (
    tester,
  ) async {
    final api = _RelayApiService();
    final hub = _RecordingHubDirectoryProvider();
    await _pumpSettings(tester, api: api, hub: hub);

    final details = find.text(_t(tester, 'settings_remote_reachable_details'));
    Future<void> openRelayDetails() async {
      await _openSection(tester, 'settings_network_title');
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
    await _goBack(tester);
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

  group('one place per setting', () {
    testWidgets('Features keeps only the module switches', (tester) async {
      await _pumpSettings(tester);
      await _openSection(tester, 'modules');

      expect(find.text(_t(tester, 'quotes_module')), findsOneWidget);
      // Each moved to the section of what it changes.
      for (final key in [
        'auto_approve_loans_title',
        'module_digital_formats',
        'settings_notif_enabled',
        'mcp_integration',
        'module_operation_log_viewer',
        'settings_show_not_owned_books',
        'carousel_peer_lib_title',
      ]) {
        expect(find.text(_t(tester, key)), findsNothing, reason: key);
      }
    });

    for (final (sectionKey, settingKey) in [
      ('modules_group_lending', 'auto_approve_loans_title'),
      ('content', 'module_digital_formats'),
      ('content', 'duplicates_title'),
      ('theme_title', 'settings_show_not_owned_books'),
      ('settings_notifications', 'settings_notif_enabled'),
      ('settings_account_devices_title', 'account_share_access_title'),
      ('modules_group_advanced', 'mcp_integration'),
      ('modules_group_advanced', 'system_reset_title'),
    ]) {
      testWidgets('$settingKey sits in $sectionKey', (tester) async {
        await _pumpSettings(tester);
        final setting = find.text(_t(tester, settingKey));
        expect(setting, findsNothing);

        await _openSection(tester, sectionKey);
        await tester.ensureVisible(setting);
        expect(setting, findsOneWidget);
      });
    }

    testWidgets('the springboard offers four shortcuts at most', (
      tester,
    ) async {
      await _pumpSettings(tester);
      expect(
        tester.widgetList(find.byType(GoalTile)).length,
        lessThanOrEqualTo(4),
      );
      // Other devices takes the reading-language tile's place; the
      // focus=language link still reaches the reading languages.
      expect(
        find.text(_t(tester, 'settings_goal_sync_devices')),
        findsOneWidget,
      );
      expect(find.text(_t(tester, 'settings_goal_language')), findsNothing);
    });

    testWidgets('a search for a moved setting opens its new section', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await tester.enterText(find.byType(TextField).first, 'mcp');
      await _settle(tester);

      final mcp = find.text(_t(tester, 'mcp_integration'));
      await tester.ensureVisible(mcp);
      expect(mcp, findsOneWidget);
      expect(find.text(_t(tester, 'modules')), findsNothing);
    });
  });

  testWidgets('a search for the version shows it under Advanced', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'BiblioGenius',
      packageName: 'com.example.bibliogenius',
      version: '1.3.0',
      buildNumber: '42',
      buildSignature: '',
    );
    await _pumpSettings(tester);
    final version = find.text('BiblioGenius v1.3.0 (42)');

    await tester.enterText(find.byType(TextField).first, 'version');
    await _settle(tester);
    await tester.ensureVisible(version);
    expect(version, findsOneWidget);

    // Any other search leaves it out.
    await tester.enterText(find.byType(TextField).first, 'mcp');
    await _settle(tester);
    expect(version, findsNothing);
  });

  group('section pages', () {
    Finder pageTitle(WidgetTester tester, String titleKey) => find.descendant(
      of: find.byType(AppBar),
      matching: find.text(_t(tester, titleKey)),
    );

    for (final section in [
      for (final group in settingsSectionGroups) ...group.sections,
    ]) {
      testWidgets('the list opens ${section.name} on its own page', (
        tester,
      ) async {
        await _pumpSettings(tester);
        await _openSection(tester, section.titleKey);

        expect(pageTitle(tester, section.titleKey), findsOneWidget);
        expect(
          find.text(_t(tester, 'settings_springboard_title')),
          findsNothing,
        );
      });
    }

    testWidgets('a link to a section page opens it', (tester) async {
      await _pumpSettings(tester, location: '/settings/backup');
      expect(pageTitle(tester, 'backup_section_title'), findsOneWidget);

      await _goBack(tester);
      expect(
        find.text(_t(tester, 'settings_springboard_title')),
        findsOneWidget,
      );
    });

    testWidgets('a link to an unknown section leads to the list', (
      tester,
    ) async {
      await _pumpSettings(tester, location: '/settings/nothing-here');
      expect(
        find.text(_t(tester, 'settings_springboard_title')),
        findsOneWidget,
      );
    });

    testWidgets('a search result title opens the whole section', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await tester.enterText(find.byType(TextField).first, 'mcp');
      await _settle(tester);
      final reset = find.text(_t(tester, 'system_reset_title'));
      expect(reset, findsNothing);

      await _openSection(tester, 'modules_group_advanced');
      expect(pageTitle(tester, 'modules_group_advanced'), findsOneWidget);
      // Unfiltered: the page shows what the search left out.
      await tester.ensureVisible(reset);
      expect(reset, findsOneWidget);

      // Back to the results, search kept.
      await _goBack(tester);
      expect(find.text(_t(tester, 'mcp_integration')), findsOneWidget);
      expect(reset, findsNothing);
    });
  });

  group('one visit at a time', () {
    Finder openLibrary() => find.widgetWithText(SwitchListTile, 'OpenLibrary');
    bool openLibraryOn(WidgetTester tester) =>
        tester.widget<SwitchListTile>(openLibrary()).value;
    // The key field is obscured: match its value, not its text.
    Finder keyField(String key) => find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == key,
    );

    testWidgets('back from a section page, the results show its changes', (
      tester,
    ) async {
      await _pumpSettings(tester, api: _StoredSearchApiService());
      await tester.enterText(
        find.byType(TextField).first,
        _t(tester, 'search_sources'),
      );
      await _settle(tester);
      expect(openLibraryOn(tester), isTrue);

      await _openSection(tester, 'settings_find_books_title');
      await tester.ensureVisible(openLibrary());
      await tester.tap(openLibrary());
      await _settle(tester);
      expect(openLibraryOn(tester), isFalse);

      await _goBack(tester);
      expect(openLibraryOn(tester), isFalse);
    });

    testWidgets('a new visit forgets what the last one loaded', (tester) async {
      final api = _StoredSearchApiService()
        ..googleKey = 'OLD-KEY'
        // Google Books on, so its key field shows.
        ..sources = {'openlibrary': false, 'google_books': true};
      await _pumpSettings(tester, api: api);
      await _openSection(tester, 'settings_find_books_title');
      expect(keyField('OLD-KEY'), findsOneWidget);
      expect(openLibraryOn(tester), isFalse);

      // A reset, say: the backend no longer stores either.
      api
        ..googleKey = ''
        ..sources = {};
      final router = GoRouter.of(tester.element(find.byType(Navigator).first));
      router.go('/elsewhere');
      await _settle(tester);
      router.go('/settings');
      await _settle(tester);

      await _openSection(tester, 'settings_find_books_title');
      expect(keyField('OLD-KEY'), findsNothing);
      expect(openLibraryOn(tester), isTrue);
    });
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
