import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
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
  Future<String?> getDeviceFingerprint() async => 'fp-test';

  @override
  Future<String?> getAppVersion() async => '1.0.0';
}

/// FFI mock that returns a 404 from the hub for any [hubDirectoryGetProfile]
/// call by default, and counts invocations so the tests can assert the
/// negative cache short-circuits subsequent calls.
class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  int getProfileCallCount = 0;
  final List<String> getProfileArgs = [];

  /// nodeIds for which the mock should return a successful profile instead of
  /// throwing the 404 error. Returned profiles have a deterministic name
  /// `Found {nodeId}` so tests can correlate cache state with the source.
  final Set<String> hydratedNodeIds = {};

  @override
  Future<frb.FrbHubProfile?> hubDirectoryGetProfile(String nodeId) async {
    getProfileCallCount++;
    getProfileArgs.add(nodeId);
    if (hydratedNodeIds.contains(nodeId)) {
      return frb.FrbHubProfile(
        nodeId: nodeId,
        displayName: 'Found $nodeId',
        bookCount: 0,
        requiresApproval: false,
      );
    }
    // Mirror the Rust-side error string format: HubDirectoryError::Hub
    // formats as "Hub error <code>: <body>". The provider checks for the
    // "Hub error 404" substring to flip the negative cache.
    throw 'Hub error 404: profile not found';
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<(HubDirectoryProvider, _MockFfiService)> _createProvider() async {
  SharedPreferences.setMockInitialValues({});
  final ffi = _MockFfiService();
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  return (provider, ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HubDirectoryProvider negative cache (point 9)', () {
    test(
      'refreshName: a 404 is cached, second call short-circuits',
      () async {
        final (provider, ffi) = await _createProvider();

        await provider.refreshName('ghost-node-id');
        expect(ffi.getProfileCallCount, 1);

        // The same nodeId must not hit the FFI a second time within the
        // TTL window. Stops the 116-hits-per-ghost pattern observed in
        // production hub_events.
        await provider.refreshName('ghost-node-id');
        expect(ffi.getProfileCallCount, 1);
      },
    );

    test(
      'refreshName: a successful refresh clears the negative cache entry',
      () async {
        final (provider, ffi) = await _createProvider();

        await provider.refreshName('flapping-node-id');
        expect(ffi.getProfileCallCount, 1);

        // Peer reappears on the hub between calls (NithaM scenario).
        ffi.hydratedNodeIds.add('flapping-node-id');

        // The cache entry is still there from the 404, so the immediate
        // call short-circuits. This is the trade-off documented in the
        // module: a peer that flaps is muted for one TTL window.
        await provider.refreshName('flapping-node-id');
        expect(ffi.getProfileCallCount, 1);

        // invalidateNameCache simulates the user explicitly retrying
        // (pull-to-refresh on a list). The negative cache must be wiped
        // so a previously-not-found peer is given a chance again.
        provider.invalidateNameCache();
        await provider.refreshName('flapping-node-id');
        expect(ffi.getProfileCallCount, 2);
      },
    );
  });
}
