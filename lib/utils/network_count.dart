import '../models/contact.dart';

/// Counts the user's network for the dashboard "Contacts" stat.
///
/// A "contact" on the dashboard is the union of two distinct stores:
///   * manual contacts (borrowers / users) saved in the `contacts` table, and
///   * connected peers (paired libraries) saved in the `peers` table.
///
/// The two are NOT mirrored automatically: a connected peer only gets a
/// `type = 'Library'` row in the `contacts` table lazily, when a loan/request
/// happens. Counting the `contacts` table alone therefore undercounts the
/// network (connected peers without a loan are invisible).
///
/// This helper sums:
///   * active manual contacts, excluding peer-mirror `'Library'` rows so a peer
///     that did have a loan is not counted twice, and
///   * connected peers (`connection_status != 'pending'`), deduplicated by
///     `library_uuid` (the same device can have several rows after port
///     changes), mirroring the Network screen.
///
/// [peers] is the raw list from `ApiService.getPeers()` (`data` field).
int countNetworkContacts(List<Contact> contacts, List<dynamic> peers) {
  final manualCount = contacts.where((c) {
    if (!c.isActive) return false;
    return c.type.toLowerCase() != 'library';
  }).length;

  final seenUuids = <String>{};
  var peerCount = 0;
  for (final raw in peers) {
    if (raw is! Map) continue;
    final connectionStatus = raw['connection_status'];
    // Only count connected peers; pending pairings are not yet members.
    if (connectionStatus == 'pending') continue;
    final uuid = raw['library_uuid'];
    if (uuid is String && uuid.isNotEmpty) {
      if (!seenUuids.add(uuid)) continue;
    }
    peerCount++;
  }

  return manualCount + peerCount;
}
