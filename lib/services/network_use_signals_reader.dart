import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ffi_service.dart';
import 'online_services_consent.dart';

/// Preference behind the "Public directory" switch
/// (`HubDirectoryProvider.setHubEnabled`).
const kDirectoryEnabledPrefKey = 'hub_directory_enabled';

/// Reads the network use of this installation (ADR-073 D3) from the device:
/// one preference and three local lookups, no request to the hub.
///
/// One true signal is enough, whatever happened to the others. With none
/// true, a lookup that failed makes the whole answer unknown (it throws):
/// "no peer" and "the peers could not be read" must not look alike, since a
/// real no leads to removing the local relay configuration.
///
/// A peer only counts when [wasRegistered] says an earlier build already
/// registered this installation on the hub. Another device can create a
/// peer row here without this user doing anything (an incoming connection
/// request is accepted by default): on an installation that never
/// registered, such a row would turn someone else's gesture into this
/// user's consent. There, pairing is a gesture that records the consent.
Future<NetworkUseSignals> readNetworkUseSignals({
  required Future<bool> Function() hasPeer,
  required Future<bool> Function() wasRegistered,
  required Future<bool> Function() isListed,
  required Future<bool> Function() hasAccount,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final directoryEnabled = prefs.getBool(kDirectoryEnabledPrefKey) ?? false;

  Object? failure;
  Future<bool> lookup(Future<bool> Function() read) async {
    try {
      return await read();
    } catch (e) {
      failure ??= e;
      return false;
    }
  }

  final signals = NetworkUseSignals(
    directoryEnabled: directoryEnabled,
    hasPeer: await lookup(wasRegistered) && await lookup(hasPeer),
    isListed: await lookup(isListed),
    hasAccount: await lookup(hasAccount),
  );
  if (!signals.any && failure != null) {
    throw StateError('network use could not be read: $failure');
  }
  return signals;
}

/// The reader wired on the real device. [getPeers] fetches the local peer
/// list from the embedded server, in its strict form (a failed read is an
/// error, not an empty list); null in contexts that have no local server
/// (some tests): the peers then count as unreadable.
Future<NetworkUseSignals> Function() deviceNetworkUseReader({
  required Future<Response<dynamic>> Function()? getPeers,
  required FfiService ffi,
}) {
  return () => readNetworkUseSignals(
    hasPeer: () async {
      if (getPeers == null) throw StateError('no local API');
      final res = await getPeers();
      if (res.statusCode != 200) {
        throw StateError('peers unreadable (${res.statusCode})');
      }
      final data = res.data;
      final list = (data is Map ? data['data'] : data) as List? ?? const [];
      return list.isNotEmpty;
    },
    // The relay configuration counts too: an earlier build drops the
    // registration row on a refused token while the mailbox its peers
    // write to stays. This build only creates one with the consent, and
    // forgets it on the first "no".
    wasRegistered: () async =>
        await ffi.hubDirectoryGetConfigStrict() != null ||
        await ffi.getRelayConfigStrict() != null,
    isListed: () async =>
        (await ffi.hubDirectoryGetConfigStrict())?.isListed == true,
    hasAccount: () async {
      final status = jsonDecode(await ffi.accountStatus());
      return status is Map && status['signed_in'] == true;
    },
  );
}
