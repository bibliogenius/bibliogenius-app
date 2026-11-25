import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user decided about the online services (ADR-073 D1): every call
/// that registers this installation on the hub or sends it library data.
enum OnlineServicesChoice {
  /// Never asked. The answer is then inferred from what the installation
  /// already does on the network (ADR-073 D3).
  unset,

  /// Said yes to the dialog shown at a network action (ADR-073 D2).
  granted,

  /// Said yes once, then took it back. Network use no longer counts.
  withdrawn,
}

/// A registration on the hub, as this device names it: the library id of
/// its profile and the relay mailbox of this device. Either may be absent.
typedef HubRegistrationIds = ({String? nodeId, String? mailboxUuid});

/// Outcome of [OnlineServicesConsent.decide].
enum OnlineServicesDecision {
  /// The calls may go out.
  allowed,

  /// The user withdrew, or never asked and uses nothing on the network.
  refused,

  /// The choice is unset and the device could not be read.
  unknown,
}

/// What this installation already does on the network, read from the device
/// alone. Any of these stands for a consent while the choice is unset: the
/// user who paired with a peer, or opened the directory, did choose the hub.
///
/// Sharing the scores is not one of them: the switch sends nothing to the
/// hub, the scores only travel to peers, and a peer is already a signal.
/// On its own it would register someone who has nobody to share with.
@immutable
class NetworkUseSignals {
  const NetworkUseSignals({
    this.hasPeer = false,
    this.directoryEnabled = false,
    this.isListed = false,
    this.hasAccount = false,
  });

  /// At least one peer, whatever its status, on an installation that an
  /// earlier build had already registered on the hub (see
  /// `readNetworkUseSignals` for why a peer alone is not enough).
  final bool hasPeer;

  /// The "Public directory" switch of the settings.
  final bool directoryEnabled;

  /// The library is published in the directory.
  final bool isListed;

  /// This device belongs to an encrypted account.
  final bool hasAccount;

  /// The same signals with the peer left out.
  NetworkUseSignals withoutPeer() => NetworkUseSignals(
    directoryEnabled: directoryEnabled,
    isListed: isListed,
    hasAccount: hasAccount,
  );

  bool get any => hasPeer || directoryEnabled || isListed || hasAccount;

  @override
  String toString() =>
      'NetworkUseSignals(hasPeer: $hasPeer, '
      'directoryEnabled: $directoryEnabled, isListed: $isListed, '
      'hasAccount: $hasAccount)';
}

/// The rule itself, kept pure: an explicit choice wins, and only an unset
/// choice falls back on network use.
bool onlineServicesAllowed(
  OnlineServicesChoice choice,
  NetworkUseSignals signals,
) {
  switch (choice) {
    case OnlineServicesChoice.granted:
      return true;
    case OnlineServicesChoice.withdrawn:
      return false;
    case OnlineServicesChoice.unset:
      return signals.any;
  }
}

/// The online services consent of this installation (ADR-073).
///
/// Per device: the choice lives in the local preferences, is not part of
/// the backup, and does not travel with an encrypted account.
///
/// While the choice is unset, the inference is redone at each launch and
/// never written down, so a restore that brings peers back is seen at the
/// next launch without any gesture.
class OnlineServicesConsent {
  OnlineServicesConsent({required this.readSignals});

  /// Preference holding the explicit choice. Absent while unset.
  static const prefKey = 'online_services_consent';

  /// Set once this installation was judged "no" (see [rememberSilence]).
  static const peersIgnoredPrefKey = 'online_services_peers_ignored';

  /// Set while a withdrawal still has something to delete on the hub (see
  /// [rememberPendingRemoval]). Absent otherwise.
  static const removalPendingPrefKey = 'online_services_removal_pending';

  /// Set when a withdrawal ended without the hub confirming the deletion,
  /// with nothing left to try (see [rememberUnconfirmedRemoval]).
  static const removalUnconfirmedPrefKey =
      'online_services_removal_unconfirmed';

  static const _granted = 'granted';
  static const _withdrawn = 'withdrawn';

  /// Reads the network use of this installation from the device.
  final Future<NetworkUseSignals> Function() readSignals;

  /// Test suites written before the consent existed drive the hub paths of
  /// the providers directly; their directory sets this so they keep
  /// testing what they tested. Never set outside tests.
  @visibleForTesting
  static bool debugAlwaysAllowed = false;

  /// A positive inference holds for the session. A negative one is looked
  /// at again, since a pairing may have completed in the meantime.
  bool _inferredAllowed = false;

  Future<OnlineServicesChoice> choice() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(prefKey)) {
      case _granted:
        return OnlineServicesChoice.granted;
      case _withdrawn:
        return OnlineServicesChoice.withdrawn;
      default:
        // Anything else, a stray value included, is not a yes.
        return OnlineServicesChoice.unset;
    }
  }

  /// Whether the calls of ADR-073 D1 may go out now. Not knowing is not a
  /// consent: [OnlineServicesDecision.unknown] allows nothing.
  Future<bool> isAllowed() async =>
      await decide() == OnlineServicesDecision.allowed;

  /// Whether a consent that holds was never given in so many words: the
  /// choice is unset and the yes comes from network use (ADR-073 D3). Only
  /// meaningful when [isAllowed] answered true.
  Future<bool> isInferred() async =>
      !debugAlwaysAllowed && await choice() == OnlineServicesChoice.unset;

  /// The decision, telling a real "no" from "could not tell". Only a real
  /// no may lead to removing something from the device (the local relay
  /// configuration): a database that is not ready yet must never be read
  /// as "this user has no peer".
  Future<OnlineServicesDecision> decide() async {
    if (debugAlwaysAllowed) return OnlineServicesDecision.allowed;
    final current = await choice();
    if (current == OnlineServicesChoice.granted) {
      return OnlineServicesDecision.allowed;
    }
    if (current == OnlineServicesChoice.withdrawn) {
      return OnlineServicesDecision.refused;
    }
    if (_inferredAllowed) return OnlineServicesDecision.allowed;
    try {
      var signals = await readSignals();
      if (signals.hasPeer && await _peersIgnored()) {
        signals = signals.withoutPeer();
      }
      _inferredAllowed = onlineServicesAllowed(current, signals);
    } catch (e) {
      debugPrint('OnlineServicesConsent: signals unreadable: $e');
      return OnlineServicesDecision.unknown;
    }
    if (_inferredAllowed) return OnlineServicesDecision.allowed;
    // A "no" read from the device is remembered here, wherever it was
    // asked from, so that no later peer row can turn it around.
    await rememberSilence();
    return OnlineServicesDecision.refused;
  }

  /// Records a yes given at a network action.
  Future<void> grant() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, _granted);
    await prefs.remove(peersIgnoredPrefKey);
    // A registration the user asks for again is not to be deleted.
    await prefs.remove(removalPendingPrefKey);
    await prefs.remove(removalUnconfirmedPrefKey);
  }

  /// Remembers that this installation was judged "no" and went silent.
  /// From then on a peer no longer stands for a consent: another device can
  /// create a peer row here at any time (an incoming connection request),
  /// and that must not reopen the hub behind the user's back. What the
  /// user does on this device (the directory switch, an account, any
  /// network gesture) still counts.
  Future<void> rememberSilence() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(peersIgnoredPrefKey) == true) return;
    await prefs.setBool(peersIgnoredPrefKey, true);
  }

  /// Lifts [rememberSilence]. Called when the user restores a backup: the
  /// peers it brings back are theirs, and are looked at again at the next
  /// launch.
  static Future<void> forgetSilence() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(peersIgnoredPrefKey);
  }

  Future<bool> _peersIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(peersIgnoredPrefKey) == true;
  }

  /// Records that the consent was taken back. Holds whatever the
  /// installation does on the network afterwards, and through a restored
  /// backup (the choice is not part of it), until a yes is given again.
  Future<void> withdraw() async {
    _inferredAllowed = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, _withdrawn);
  }

  /// Puts back the choice [previous] a withdrawal replaced, when that
  /// withdrawal turned out to be refused: nothing was deleted, so nothing
  /// is left pending either.
  Future<void> restore(OnlineServicesChoice previous) async {
    final prefs = await SharedPreferences.getInstance();
    switch (previous) {
      case OnlineServicesChoice.granted:
        await prefs.setString(prefKey, _granted);
      case OnlineServicesChoice.withdrawn:
        await prefs.setString(prefKey, _withdrawn);
      case OnlineServicesChoice.unset:
        await prefs.remove(prefKey);
    }
    if (previous != OnlineServicesChoice.withdrawn) {
      await prefs.remove(removalPendingPrefKey);
    }
  }

  /// Remembers which registration a withdrawal still has to delete on the
  /// hub: the library id and the relay mailbox read on this device when
  /// the user withdrew. Written before the deletion is asked, so an app
  /// killed in between, or a hub that does not answer, leaves it to be
  /// tried again. Naming the registration matters: a backup restored
  /// meanwhile can bring another library's rows, whose tokens must never
  /// be used for this deletion.
  Future<void> rememberPendingRemoval(HubRegistrationIds ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      removalPendingPrefKey,
      jsonEncode({'node_id': ids.nodeId, 'mailbox_uuid': ids.mailboxUuid}),
    );
  }

  /// The registration still to delete on the hub, null when there is none.
  Future<HubRegistrationIds?> pendingRemoval() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(removalPendingPrefKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (
        nodeId: decoded['node_id'] as String?,
        mailboxUuid: decoded['mailbox_uuid'] as String?,
      );
    } catch (_) {
      // Unreadable: nothing can be named, so nothing is deleted on the hub.
      return (nodeId: null, mailboxUuid: null);
    }
  }

  /// The hub refused the write token and the recovery code of this device:
  /// whether it still holds the profile cannot be told, and asking again
  /// would get the same answer. Nothing is retried; the settings keep
  /// saying so, with the page where a deletion can be asked for.
  Future<void> rememberUnconfirmedRemoval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(removalPendingPrefKey);
    await prefs.setBool(removalUnconfirmedPrefKey, true);
  }

  Future<bool> removalUnconfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(removalUnconfirmedPrefKey) == true;
  }

  Future<void> clearPendingRemoval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(removalPendingPrefKey);
  }
}
