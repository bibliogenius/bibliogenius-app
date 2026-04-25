import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks
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

  /// Each entry records the filter args of one hubDirectoryList call.
  final List<({String? country, int? cityId, String? search})> calls = [];
  List<frb.FrbHubProfile> nextResult = const [];

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async {
    calls.add((country: country, cityId: cityId, search: search));
    return nextResult;
  }
}

Future<HubDirectoryProvider> _provider() async {
  SharedPreferences.setMockInitialValues({});
  AuthService.storage = MockSecureStorage();
  return HubDirectoryProvider(
    ffi: _MockFfiService(),
    deviceService: _MockDeviceService(),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('loadDirectory location filters (ADR-035 Phase 2)', () {
    test('forwards country and cityId to FFI', () async {
      SharedPreferences.setMockInitialValues({});
      AuthService.storage = MockSecureStorage();
      final ffi = _MockFfiService();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      );

      await provider.loadDirectory(country: 'FR', cityId: 2988507);

      expect(ffi.calls, hasLength(1));
      expect(ffi.calls.single.country, 'FR');
      expect(ffi.calls.single.cityId, 2988507);
    });

    test('uppercases the country code so the picker output is canonical',
        () async {
      SharedPreferences.setMockInitialValues({});
      AuthService.storage = MockSecureStorage();
      final ffi = _MockFfiService();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      );

      await provider.loadDirectory(country: 'fr');

      expect(ffi.calls.single.country, 'FR');
      expect(provider.filterCountry, 'FR');
    });

    test('exposes hasActiveLocationFilter when at least one filter is set',
        () async {
      final provider = await _provider();
      expect(provider.hasActiveLocationFilter, false,
          reason: 'baseline: no filter active');

      await provider.loadDirectory(country: 'FR');
      expect(provider.hasActiveLocationFilter, true);
      expect(provider.filterCityId, isNull,
          reason: 'country alone must not imply a city');

      await provider.loadDirectory(cityId: 2988507);
      expect(provider.filterCityId, 2988507);
    });

    test('preserves existing filters when reloading with only a search',
        () async {
      SharedPreferences.setMockInitialValues({});
      AuthService.storage = MockSecureStorage();
      final ffi = _MockFfiService();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      );

      await provider.loadDirectory(country: 'FR', cityId: 2988507);
      await provider.loadDirectory(search: 'voltaire');

      expect(ffi.calls.last.country, 'FR',
          reason:
              'A search-only refresh inside a filtered view must not silently '
              'broaden the result set across France or beyond');
      expect(ffi.calls.last.cityId, 2988507);
      expect(ffi.calls.last.search, 'voltaire');
    });

    test('clearLocationFilter wipes both country and cityId in one call',
        () async {
      SharedPreferences.setMockInitialValues({});
      AuthService.storage = MockSecureStorage();
      final ffi = _MockFfiService();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      );

      await provider.loadDirectory(country: 'FR', cityId: 2988507);
      await provider.loadDirectory(clearLocationFilter: true);

      expect(provider.filterCountry, isNull);
      expect(provider.filterCityId, isNull);
      expect(provider.hasActiveLocationFilter, false);
      expect(ffi.calls.last.country, isNull);
      expect(ffi.calls.last.cityId, isNull);
    });

    test('cityId=0 acts as the "drop city, keep country" sentinel', () async {
      SharedPreferences.setMockInitialValues({});
      AuthService.storage = MockSecureStorage();
      final ffi = _MockFfiService();
      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
      );

      await provider.loadDirectory(country: 'FR', cityId: 2988507);
      await provider.loadDirectory(cityId: 0);

      expect(provider.filterCountry, 'FR',
          reason: 'country must survive the city-only clear');
      expect(provider.filterCityId, isNull);
      expect(ffi.calls.last.country, 'FR');
      expect(ffi.calls.last.cityId, isNull);
    });
  });
}
