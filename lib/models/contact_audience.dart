import 'hub_directory.dart';

/// Who receives the owner's contact card (ADR-067).
///
/// The card itself belongs to the library, not to the directory: it is one
/// piece of data, and the audience decides to which followers it is sealed.
/// Two audiences exist:
///   - [pairedPeers]: followers that are also accepted P2P pairings (the same
///     identities ADR-053 auto-follows and auto-approves);
///   - [directoryFollowers]: every other approved follower of the directory.
///
/// The sealed blob on the hub is a projection of this choice, computed on the
/// client. The hub knows nothing about it.
class ContactAudience {
  final bool pairedPeers;
  final bool directoryFollowers;

  const ContactAudience({
    required this.pairedPeers,
    required this.directoryFollowers,
  });

  /// Default for a card created from scratch: paired peers only.
  static const fresh = ContactAudience(
    pairedPeers: true,
    directoryFollowers: false,
  );

  /// Default for a card that existed before audiences did. Its current
  /// followers already hold it, so both audiences stay on: introducing the
  /// choice must not silently take the card back from anyone.
  static const legacy = ContactAudience(
    pairedPeers: true,
    directoryFollowers: true,
  );

  static const _paired = 'paired';
  static const _directory = 'directory';

  /// Stored as a single string so the backup restore path, which re-applies
  /// String and int values only, carries it back.
  String encode() =>
      [if (pairedPeers) _paired, if (directoryFollowers) _directory].join(',');

  factory ContactAudience.decode(String raw) {
    final parts = raw.split(',').map((s) => s.trim()).toSet();
    return ContactAudience(
      pairedPeers: parts.contains(_paired),
      directoryFollowers: parts.contains(_directory),
    );
  }

  ContactAudience copyWith({bool? pairedPeers, bool? directoryFollowers}) =>
      ContactAudience(
        pairedPeers: pairedPeers ?? this.pairedPeers,
        directoryFollowers: directoryFollowers ?? this.directoryFollowers,
      );

  /// Whether the follower [followerNodeId] may receive the card.
  ///
  /// A paired peer is also a follower, so the directory audience covers it
  /// too: ticking "directory followers" means every approved follower.
  bool includes(String followerNodeId, Set<String> pairedUuids) =>
      directoryFollowers ||
      (pairedPeers && pairedUuids.contains(followerNodeId));

  @override
  bool operator ==(Object other) =>
      other is ContactAudience &&
      other.pairedPeers == pairedPeers &&
      other.directoryFollowers == directoryFollowers;

  @override
  int get hashCode => Object.hash(pairedPeers, directoryFollowers);
}

/// What a contact re-broadcast must send to the hub.
class ContactSyncPlan {
  /// Active followers that must receive a freshly sealed card.
  final List<HubFollow> seal;

  /// Active followers still holding a blob they must no longer have. They are
  /// sent an empty string, which the hub stores as-is and every reader
  /// version treats as "no contact".
  final List<HubFollow> clear;

  const ContactSyncPlan({required this.seal, required this.clear});

  bool get isEmpty => seal.isEmpty && clear.isEmpty;
}

/// Projects the card onto the follower list.
///
/// Only active followers are considered: the hub refuses to update any other.
/// A follower without an x25519 key cannot be sealed for; if it still holds a
/// blob and is excluded, it is cleared all the same. An excluded follower that
/// holds nothing is left alone, so a re-broadcast does not rewrite rows that
/// are already right.
ContactSyncPlan planContactSync({
  required List<HubFollow> followers,
  required Set<String> pairedUuids,
  required ContactAudience audience,
  required bool hasCard,
}) {
  final seal = <HubFollow>[];
  final clear = <HubFollow>[];
  for (final f in followers) {
    if (!f.isActive) continue;
    if (hasCard && audience.includes(f.followerNodeId, pairedUuids)) {
      final key = f.followerX25519PublicKey;
      if (key != null && key.isNotEmpty) seal.add(f);
      continue;
    }
    final blob = f.encryptedContact;
    if (blob != null && blob.isNotEmpty) clear.add(f);
  }
  return ContactSyncPlan(seal: seal, clear: clear);
}
