import 'package:bibliogenius/services/backup_prefs_whitelist.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _noUse = NetworkUseSignals();

OnlineServicesConsent _consent({
  NetworkUseSignals signals = _noUse,
  bool failReading = false,
  void Function()? onRead,
}) {
  return OnlineServicesConsent(
    readSignals: () async {
      onRead?.call();
      if (failReading) throw StateError('local database not ready');
      return signals;
    },
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('decision (ADR-073 D1, D3)', () {
    test('an installation that never used the network sends nothing', () {
      expect(
        onlineServicesAllowed(OnlineServicesChoice.unset, _noUse),
        isFalse,
      );
    });

    test('each kind of network use stands for a consent while unset', () {
      const uses = [
        NetworkUseSignals(hasPeer: true),
        NetworkUseSignals(directoryEnabled: true),
        NetworkUseSignals(isListed: true),
        NetworkUseSignals(hasAccount: true),
      ];
      for (final signals in uses) {
        expect(
          onlineServicesAllowed(OnlineServicesChoice.unset, signals),
          isTrue,
          reason: '$signals',
        );
      }
    });

    test('an explicit yes needs no network use', () {
      expect(
        onlineServicesAllowed(OnlineServicesChoice.granted, _noUse),
        isTrue,
      );
    });

    test('a withdrawal is not overridden by what the device still holds', () {
      expect(
        onlineServicesAllowed(
          OnlineServicesChoice.withdrawn,
          const NetworkUseSignals(hasPeer: true, hasAccount: true),
        ),
        isFalse,
      );
    });
  });

  group('stored choice', () {
    test('nothing stored reads as unset', () async {
      expect(await _consent().choice(), OnlineServicesChoice.unset);
    });

    test('grant and withdraw survive a restart', () async {
      await _consent().grant();
      expect(await _consent().choice(), OnlineServicesChoice.granted);
      expect(await _consent().isAllowed(), isTrue);

      await _consent().withdraw();
      expect(await _consent().choice(), OnlineServicesChoice.withdrawn);
      expect(
        await _consent(
          signals: const NetworkUseSignals(hasPeer: true),
        ).isAllowed(),
        isFalse,
      );
    });

    test('an unknown stored value reads as unset, never as a yes', () async {
      SharedPreferences.setMockInitialValues({
        OnlineServicesConsent.prefKey: 'true',
      });
      expect(await _consent().choice(), OnlineServicesChoice.unset);
      expect(await _consent().isAllowed(), isFalse);
    });
  });

  group('inference while unset', () {
    test('network use found on the device allows the calls', () async {
      final consent = _consent(signals: const NetworkUseSignals(hasPeer: true));
      expect(await consent.isAllowed(), isTrue);
      expect(
        await consent.choice(),
        OnlineServicesChoice.unset,
        reason: 'the inference is not written down: it is redone each launch',
      );
    });

    test('a yes is remembered for the session, a no is looked at again', () async {
      var signals = _noUse;
      var reads = 0;
      final consent = OnlineServicesConsent(
        readSignals: () async {
          reads++;
          return signals;
        },
      );

      expect(await consent.isAllowed(), isFalse);
      expect(await consent.isAllowed(), isFalse);
      expect(reads, 2, reason: 'the user may have turned something on since');

      // Something the user did on this device since (a peer would not
      // count any more: the "no" above is remembered).
      signals = const NetworkUseSignals(directoryEnabled: true);
      expect(await consent.isAllowed(), isTrue);
      expect(await consent.isAllowed(), isTrue);
      expect(reads, 3, reason: 'once allowed, the signals are not read again');
    });

    test('signals that cannot be read allow nothing', () async {
      expect(await _consent(failReading: true).isAllowed(), isFalse);
    });

    test('unreadable signals are "unknown", never a no', () async {
      // A real no leads to removing the local relay configuration: a
      // database that is not ready must not be taken for "no peer".
      expect(
        await _consent(failReading: true).decide(),
        OnlineServicesDecision.unknown,
      );
      expect(await _consent().decide(), OnlineServicesDecision.refused);
      expect(
        await _consent(
          signals: const NetworkUseSignals(hasAccount: true),
        ).decide(),
        OnlineServicesDecision.allowed,
      );
    });

    test('an explicit choice never reads the signals', () async {
      var reads = 0;
      final consent = _consent(onRead: () => reads++);
      await consent.grant();
      expect(await consent.isAllowed(), isTrue);
      await consent.withdraw();
      expect(await consent.isAllowed(), isFalse);
      expect(reads, 0);
    });
  });

  group('a remembered "no" (peers created from outside)', () {
    const peerOnly = NetworkUseSignals(hasPeer: true);

    test('once the installation went silent, a peer no longer counts', () async {
      // Another device can create a peer row here at any time. An
      // installation already judged "no" must not be reopened by it.
      await _consent().rememberSilence();

      final consent = _consent(signals: peerOnly);
      expect(await consent.decide(), OnlineServicesDecision.refused);
    });

    test('any "no" read from the device is remembered, wherever it is '
        'asked', () async {
      // Not only at startup: a gate checked from a screen, or the check
      // made before the relay mailbox, sees the same "no".
      expect(await _consent().decide(), OnlineServicesDecision.refused);

      expect(
        await _consent(signals: peerOnly).decide(),
        OnlineServicesDecision.refused,
      );
    });

    test('an unreadable device remembers nothing', () async {
      expect(
        await _consent(failReading: true).decide(),
        OnlineServicesDecision.unknown,
      );

      expect(await _consent(signals: peerOnly).isAllowed(), isTrue);
    });

    test('what the user does on this device still counts', () async {
      await _consent().rememberSilence();

      for (final signals in const [
        NetworkUseSignals(hasPeer: true, directoryEnabled: true),
        NetworkUseSignals(hasAccount: true),
        NetworkUseSignals(isListed: true),
      ]) {
        expect(
          await _consent(signals: signals).isAllowed(),
          isTrue,
          reason: '$signals',
        );
      }
    });

    test('a gesture of the user lifts it', () async {
      await _consent().rememberSilence();
      await _consent().grant();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(OnlineServicesConsent.peersIgnoredPrefKey), isNull);
    });

    test('restoring a backup lifts it: restored peers are seen again', () async {
      await _consent().rememberSilence();
      await OnlineServicesConsent.forgetSilence();

      expect(await _consent(signals: peerOnly).isAllowed(), isTrue);
    });

    test('it stays on the device', () {
      expect(
        kBackupPrefsBlacklist,
        contains(OnlineServicesConsent.peersIgnoredPrefKey),
      );
    });
  });

  test('the choice stays on the device', () {
    // Per device (ADR-073): a restored archive must not carry a consent, or
    // a withdrawal, given on another installation.
    expect(kBackupPrefsBlacklist, contains(OnlineServicesConsent.prefKey));
    expect(
      kBackupPrefsWhitelist,
      isNot(contains(OnlineServicesConsent.prefKey)),
    );
  });
}
