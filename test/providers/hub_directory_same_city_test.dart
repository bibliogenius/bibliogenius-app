import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks (mirrors hub_directory_filter_test.dart, with response stubs added so
// loadSameCityHighlight can resolve a real list of profiles)
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

  /// Each entry records the args of one hubDirectoryList call. Used to assert
  /// that the same-city fetch is keyed on cityId only (no country, no search).
  final List<({String? country, int? cityId, String? search, int limit})>
  calls = [];

  /// Routed response: `cityIdResults` is returned when the call carries a
  /// city filter, `defaultResults` for any other call. Lets a single test
  /// stub both the main list and the same-city probe at once.
  List<frb.FrbHubProfile> defaultResults = const [];
  List<frb.FrbHubProfile> cityIdResults = const [];

  /// When non-null, the next `hubDirectoryList` call throws this. Reset after
  /// firing so a second call returns normally.
  Object? nextError;

  /// Local hub config returned by `hubDirectoryGetConfig`; tests use it to
  /// give the provider a known `nodeId` so the self-filter can be exercised.
  frb.FrbDirectoryConfig? existingConfig;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      existingConfig;

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async {
    calls.add((country: country, cityId: cityId, search: search, limit: limit));
    final err = nextError;
    if (err != null) {
      nextError = null;
      throw err;
    }
    return cityId != null ? cityIdResults : defaultResults;
  }
}

frb.FrbHubProfile _profile({
  required String nodeId,
  String? country = 'FR',
  int? cityId = 2988507, // GeoNames id for Paris
  String displayName = 'Lib',
}) {
  return frb.FrbHubProfile(
    nodeId: nodeId,
    displayName: displayName,
    bookCount: 10,
    locationCountry: country,
    locationCityId: cityId,
    requiresApproval: false,
  );
}

Future<({HubDirectoryProvider provider, _MockFfiService ffi})> _setup({
  int? localCityId,
  Map<String, Object> extraPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (localCityId != null) 'hub_local_location_city_id': localCityId,
    ...extraPrefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await provider.loadLocalCityId();
  return (provider: provider, ffi: ffi);
}

// ---------------------------------------------------------------------------
// Tests - loadSameCityHighlight contract
// ---------------------------------------------------------------------------

void main() {
  group('loadSameCityHighlight - guard rails', () {
    test(
      'skips the fetch entirely when the user has not picked a city',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: null);

        await provider.loadSameCityHighlight();

        expect(
          ffi.calls,
          isEmpty,
          reason:
              'No city = no banner = no useless network round-trip. The whole '
              'feature must stay invisible to legacy / fresh-install users.',
        );
        expect(provider.sameCityProfiles, isEmpty);
        expect(provider.sameCityCount, isNull);
        expect(provider.shouldShowSameCityBanner, isFalse);
      },
    );

    test(
      'swallows fetch errors so a hub blip cannot crash the directory',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.nextError = Exception('hub down');

        await provider.loadSameCityHighlight();

        expect(provider.sameCityProfiles, isEmpty);
        expect(
          provider.shouldShowSameCityBanner,
          isFalse,
          reason: 'failed probe must degrade silently, not surface an error',
        );
      },
    );
  });

  group('loadSameCityHighlight - fetch shape', () {
    test(
      'queries the hub with cityId + the cap+1 page (no country, no search)',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = [_profile(nodeId: 'peer-1')];

        await provider.loadSameCityHighlight();

        expect(ffi.calls, hasLength(1));
        final call = ffi.calls.single;
        expect(call.cityId, 2988507);
        expect(
          call.country,
          isNull,
          reason:
              'GeoNames id is globally unique - sending country alongside '
              'would duplicate state and risk drift if the picker moves the '
              'city across borders later',
        );
        expect(call.search, isNull);
        expect(
          call.limit,
          11,
          reason: 'cap (10) + 1 sentinel so we can render "10+" precisely',
        );
      },
    );

    test('hides the user own profile from the same-city list', () async {
      final (:provider, :ffi) = await _setup(localCityId: 2988507);
      // Plant a registered config so the provider knows what "self" is.
      // Without this, the same-city count is off by +1 for any user who
      // is themselves listed in the directory in their own city.
      ffi.existingConfig = const frb.FrbDirectoryConfig(
        nodeId: 'me-self',
        isListed: true,
        requiresApproval: false,
        acceptFrom: 'anyone',
        allowBorrowing: true,
      );
      await provider.loadConfig();

      ffi.cityIdResults = [
        _profile(nodeId: 'me-self'),
        _profile(nodeId: 'peer-A'),
        _profile(nodeId: 'peer-B'),
      ];

      await provider.loadSameCityHighlight();

      expect(
        provider.sameCityProfiles.map((p) => p.nodeId),
        equals(['peer-A', 'peer-B']),
        reason:
            'Self must be stripped, mirroring the main paginated list. The '
            'banner promises peers, not a mirror of the user own profile.',
      );
    });

    test(
      'exposes the country of the first same-city peer for the filter CTA',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = [
          _profile(nodeId: 'peer-1', country: 'FR'),
          _profile(nodeId: 'peer-2', country: 'FR'),
        ];

        await provider.loadSameCityHighlight();

        expect(
          provider.sameCityCountryHint,
          'FR',
          reason:
              'The "Voir" CTA passes country+cityId so the active-filter '
              'chip renders as "FR Paris" rather than "Paris" alone. We '
              'derive the country from the first peer instead of carrying '
              'a second source of truth alongside localCityId.',
        );
      },
    );
  });

  group('sameCityCount formatting', () {
    test('renders the exact count when at or below the cap', () async {
      final (:provider, :ffi) = await _setup(localCityId: 2988507);
      ffi.cityIdResults = List.generate(7, (i) => _profile(nodeId: 'peer-$i'));

      await provider.loadSameCityHighlight();

      expect(provider.sameCityCount, 7);
      expect(provider.sameCityHasMore, isFalse);
    });

    test('renders the saturated label when the cap is exceeded', () async {
      final (:provider, :ffi) = await _setup(localCityId: 2988507);
      // 11 results = the sentinel +1 fired, so we know there are at least
      // (cap + 1) libraries in the city.
      ffi.cityIdResults = List.generate(11, (i) => _profile(nodeId: 'peer-$i'));

      await provider.loadSameCityHighlight();

      expect(
        provider.sameCityCount,
        10,
        reason: 'visible count is the cap, not the raw payload length',
      );
      expect(
        provider.sameCityHasMore,
        isTrue,
        reason: 'UI uses this to switch from "X" to "X+" wording',
      );
    });
  });

  group('shouldShowSameCityBanner - visibility rules', () {
    test(
      'false when no peer matches the user city (lone library in town)',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = const [];

        await provider.loadSameCityHighlight();

        expect(
          provider.shouldShowSameCityBanner,
          isFalse,
          reason: '"There are 0 libraries in your city" is bad UX, hide it',
        );
      },
    );

    test(
      'false when the directory filter already targets the user city',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = [_profile(nodeId: 'peer-1')];
        ffi.defaultResults = const [];

        await provider.loadSameCityHighlight();
        expect(provider.shouldShowSameCityBanner, isTrue);

        // User clicks "Voir" - the filter is now applied. The banner that
        // told them about the city becomes a duplicate of the active filter.
        await provider.loadDirectory(country: 'FR', cityId: 2988507);

        expect(
          provider.shouldShowSameCityBanner,
          isFalse,
          reason:
              'Once the filter is active, the banner only adds noise; the '
              'whole list IS the same-city subset.',
        );
      },
    );

    test('true once the active filter is cleared', () async {
      final (:provider, :ffi) = await _setup(localCityId: 2988507);
      ffi.cityIdResults = [_profile(nodeId: 'peer-1')];

      await provider.loadSameCityHighlight();
      await provider.loadDirectory(country: 'FR', cityId: 2988507);
      expect(provider.shouldShowSameCityBanner, isFalse);

      await provider.loadDirectory(clearLocationFilter: true);

      expect(provider.shouldShowSameCityBanner, isTrue);
    });
  });

  group('setLocalCityId integration', () {
    test(
      'refreshes the same-city probe when the user changes their city',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = [_profile(nodeId: 'peer-paris-1')];
        await provider.loadSameCityHighlight();
        expect(ffi.calls, hasLength(1));

        // User opens settings and switches to Lyon (GeoNames 2996944).
        ffi.cityIdResults = [
          _profile(nodeId: 'peer-lyon-1', cityId: 2996944),
          _profile(nodeId: 'peer-lyon-2', cityId: 2996944),
        ];
        await provider.setLocalCityId(2996944);

        expect(
          ffi.calls,
          hasLength(2),
          reason:
              'setLocalCityId must re-probe so the banner count and the '
              '"Voir" target stay in sync with the new city',
        );
        expect(ffi.calls.last.cityId, 2996944);
        expect(provider.sameCityProfiles, hasLength(2));
      },
    );

    test(
      'clears the same-city state when the user removes their city',
      () async {
        final (:provider, :ffi) = await _setup(localCityId: 2988507);
        ffi.cityIdResults = [_profile(nodeId: 'peer-1')];
        await provider.loadSameCityHighlight();
        expect(provider.sameCityProfiles, isNotEmpty);

        await provider.setLocalCityId(null);

        expect(
          provider.sameCityProfiles,
          isEmpty,
          reason:
              'A null city has no peers to highlight. We must NOT keep the '
              'previous Paris peers visible after the user opted out.',
        );
        expect(provider.shouldShowSameCityBanner, isFalse);
      },
    );
  });
}
