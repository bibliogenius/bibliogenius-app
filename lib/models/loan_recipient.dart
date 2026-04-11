import 'contact.dart';

/// Represents a possible loan recipient: either a manual contact or a network peer.
sealed class LoanRecipient {
  String get displayName;
}

/// A manually created borrower contact.
class ContactRecipient extends LoanRecipient {
  final Contact contact;

  ContactRecipient(this.contact);

  @override
  String get displayName => contact.fullName;
}

/// A connected network peer (from the peers table).
class PeerRecipient extends LoanRecipient {
  final int peerId;
  final String name;
  final String? peerDisplayName;

  PeerRecipient({
    required this.peerId,
    required this.name,
    this.peerDisplayName,
  });

  @override
  String get displayName => peerDisplayName ?? name;
}
