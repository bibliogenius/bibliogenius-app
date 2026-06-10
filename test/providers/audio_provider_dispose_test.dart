import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/audio/providers/audio_provider.dart';

/// Fake Connectivity exposing a controllable stream so the test can observe
/// whether AudioProvider keeps an active subscription.
class _FakeConnectivity extends Fake implements Connectivity {
  final controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dispose() cancels the connectivity subscription (no leak)', () async {
    final conn = _FakeConnectivity();
    final provider = AudioProvider(connectivity: conn);

    // Let the async _initialize() attach the listener.
    await pumpEventQueue();
    expect(
      conn.controller.hasListener,
      isTrue,
      reason: 'provider should subscribe to connectivity during init',
    );

    provider.dispose();
    await pumpEventQueue();
    expect(
      conn.controller.hasListener,
      isFalse,
      reason: 'dispose() must cancel the subscription to avoid leaking it',
    );
  });
}
