import 'package:bibliogenius/services/network_use_signals_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> _no() async => false;
Future<bool> _yes() async => true;
Future<bool> _broken() async => throw StateError('server not started');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh installation shows no network use', () async {
    final signals = await readNetworkUseSignals(
      hasPeer: _no,
      wasRegistered: _yes,
      isListed: _no,
      hasAccount: _no,
    );
    expect(signals.any, isFalse);
  });

  test('the directory switch is read from the preferences, and sharing '
      'the scores is not a network use', () async {
    SharedPreferences.setMockInitialValues({kDirectoryEnabledPrefKey: true});
    var signals = await readNetworkUseSignals(
      hasPeer: _no,
      wasRegistered: _yes,
      isListed: _no,
      hasAccount: _no,
    );
    expect(signals.directoryEnabled, isTrue);

    // The switch sends nothing to the hub and needs a peer to share with.
    SharedPreferences.setMockInitialValues({'shareGamificationStats': true});
    signals = await readNetworkUseSignals(
      hasPeer: _no,
      wasRegistered: _yes,
      isListed: _no,
      hasAccount: _no,
    );
    expect(signals.any, isFalse);
  });

  test('each local lookup is a signal', () async {
    expect(
      (await readNetworkUseSignals(
        hasPeer: _yes,
        wasRegistered: _yes,
        isListed: _no,
        hasAccount: _no,
      )).hasPeer,
      isTrue,
    );
    expect(
      (await readNetworkUseSignals(
        hasPeer: _no,
        wasRegistered: _yes,
        isListed: _yes,
        hasAccount: _no,
      )).isListed,
      isTrue,
    );
    expect(
      (await readNetworkUseSignals(
        hasPeer: _no,
        wasRegistered: _yes,
        isListed: _no,
        hasAccount: _yes,
      )).hasAccount,
      isTrue,
    );
  });

  test('one signal is enough even when another lookup fails', () async {
    final signals = await readNetworkUseSignals(
      hasPeer: _broken,
      wasRegistered: _yes,
      isListed: _no,
      hasAccount: _yes,
    );
    expect(signals.any, isTrue);
  });

  test('no signal and a failed lookup is unknown, not "no use"', () async {
    // The peers could not be read: answering "none" here would let the
    // caller remove the relay configuration of a paired user.
    expect(
      readNetworkUseSignals(
        hasPeer: _broken,
        wasRegistered: _yes,
        isListed: _no,
        hasAccount: _no,
      ),
      throwsStateError,
    );
  });
  test('a peer counts only on an installation an earlier build registered', () async {
    // Another device can create a peer row here without this user doing
    // anything (an incoming connection request). On an installation that
    // never registered, such a row must not stand for a consent.
    final fresh = await readNetworkUseSignals(
      hasPeer: _yes,
      wasRegistered: _no,
      isListed: _no,
      hasAccount: _no,
    );
    expect(fresh.any, isFalse);

    final registeredBefore = await readNetworkUseSignals(
      hasPeer: _yes,
      wasRegistered: _yes,
      isListed: _no,
      hasAccount: _no,
    );
    expect(registeredBefore.hasPeer, isTrue);
  });

  test('a registration that cannot be read is unknown, not "never '
      'registered"', () async {
    expect(
      readNetworkUseSignals(
        hasPeer: _yes,
        wasRegistered: _broken,
        isListed: _no,
        hasAccount: _no,
      ),
      throwsStateError,
    );
  });
}
