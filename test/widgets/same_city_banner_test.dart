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
// Mocks (mirror of test/providers/hub_directory_same_city_test.dart so widget
// tests can build a real provider without bootstrapping FFI).
// ---------------------------------------------------------------------------

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

  /// Args of every hubDirectoryList call. The widget tests inspect the LAST
  /// entry to verify the "Voir" button forwards the right country + city.
  final List<({String? country, int? cityId, int limit})> calls = [];

  /// Routed response: `cityIdResults` is returned when the call carries a
  /// city filter, `defaultResults` otherwise. Lets the same provider serve
  /// both the same-city probe and any subsequent loadDirectory call.
  List<frb.FrbHubProfile> cityIdResults = const [];
  List<frb.FrbHubProfile> defaultResults = const [];

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async {
    calls.add((country: country, cityId: cityId, limit: limit));
    return cityId != null ? cityIdResults : defaultResults;
  }
}

frb.FrbHubProfile _profile({
  required String nodeId,
  String country = 'FR',
  int cityId = 2988507,
}) {
  return frb.FrbHubProfile(
    nodeId: nodeId,
    displayName: nodeId,
    bookCount: 10,
    locationCountry: country,
    locationCityId: cityId,
    requiresApproval: false,
  );
}

Future<HubDirectoryProvider> _provider({
  required int? localCityId,
  required List<frb.FrbHubProfile> cityIdResults,
  _MockFfiService? ffiOut,
}) async {
  SharedPreferences.setMockInitialValues({
    if (localCityId != null) 'hub_local_location_city_id': localCityId,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = ffiOut ?? _MockFfiService();
  ffi.cityIdResults = cityIdResults;

  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await provider.loadLocalCityId();
  await provider.loadSameCityHighlight();
  return provider;
}

Widget _harness({
  required ThemeProvider theme,
  required HubDirectoryProvider hub,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
      ],
      child: Scaffold(
        body: Builder(
          // Inner Builder so the SameCityBanner consumes the providers from
          // the test scope rather than the root context (which has none).
          builder: (context) => SameCityBanner(provider: hub),
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
        'directory_same_city_banner_one':
            'There is 1 library in your city',
        'directory_same_city_banner_other':
            'There are %d libraries in your city',
        'directory_same_city_banner_more_than':
            'There are %d+ libraries in your city',
        'directory_same_city_view_action': 'View',
        'directory_same_city_view_tooltip':
            'Filter the directory to libraries in your city',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  group('SameCityBanner rendering', () {
    testWidgets('shows the singular form for exactly 1 same-city peer',
        (tester) async {
      final hub = await _provider(
        localCityId: 2988507,
        cityIdResults: [_profile(nodeId: 'peer-1')],
      );

      await tester.pumpWidget(_harness(theme: theme, hub: hub));
      await tester.pumpAndSettle();

      expect(find.text('There is 1 library in your city'), findsOneWidget,
          reason: 'count == 1 must hit the singular i18n key, not %d=1');
    });

    testWidgets('shows the plural form with the exact count up to the cap',
        (tester) async {
      final hub = await _provider(
        localCityId: 2988507,
        cityIdResults: List.generate(7, (i) => _profile(nodeId: 'peer-$i')),
      );

      await tester.pumpWidget(_harness(theme: theme, hub: hub));
      await tester.pumpAndSettle();

      expect(find.text('There are 7 libraries in your city'), findsOneWidget);
    });

    testWidgets('shows the saturated form when the cap is exceeded',
        (tester) async {
      final hub = await _provider(
        localCityId: 2988507,
        // 11 = cap + 1 sentinel: provider sets sameCityHasMore = true
        cityIdResults:
            List.generate(11, (i) => _profile(nodeId: 'peer-$i')),
      );

      await tester.pumpWidget(_harness(theme: theme, hub: hub));
      await tester.pumpAndSettle();

      expect(find.text('There are 10+ libraries in your city'), findsOneWidget,
          reason: '"10+" wording is the whole point of the cap+1 probe');
    });
  });

  group('SameCityBanner action', () {
    testWidgets('"View" forwards country + cityId to loadDirectory',
        (tester) async {
      final ffi = _MockFfiService();
      final hub = await _provider(
        localCityId: 2988507,
        cityIdResults: [_profile(nodeId: 'peer-1', country: 'FR')],
        ffiOut: ffi,
      );
      // Drop the probe call so we only inspect the post-tap behavior.
      ffi.calls.clear();

      await tester.pumpWidget(_harness(theme: theme, hub: hub));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(ffi.calls, hasLength(1));
      final call = ffi.calls.single;
      expect(call.cityId, 2988507);
      expect(call.country, 'FR',
          reason:
              'Country is derived from the first same-city peer so the active '
              'filter chip renders as "FR City" rather than "City" alone, '
              'matching the existing two-step picker UX.');
    });
  });
}
