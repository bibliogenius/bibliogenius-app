import '../models/contact.dart';

/// Enum representing the type of network member
enum NetworkMemberType {
  borrower, // Person who borrows books (Contact type=borrower)
  library, // Library entity (Contact type=library OR Peer)
}

/// Enum representing the source of the network member data
enum NetworkMemberSource {
  local, // From Contact table (offline)
  network, // From Peer table (online/P2P)
}

/// Unified model for displaying both Contacts and Peers in a single list.
/// This is a display-focused wrapper that abstracts the underlying data source.
class NetworkMember {
  final int id;
  final String name;
  final NetworkMemberType type;
  final NetworkMemberSource source;

  // Contact-specific fields (null for network peers)
  final String? email;
  final String? phone;
  final String? notes;
  final String? address;
  final bool? isActive;

  // Peer-specific fields (null for local contacts)
  final String? url;
  final String? status; // 'connected', 'pending', 'offline'
  final String? lastSeen;

  // V4 Future: Association link
  final int? linkedPeerId;
  final int? linkedContactId;

  const NetworkMember({
    required this.id,
    required this.name,
    required this.type,
    required this.source,
    this.email,
    this.phone,
    this.notes,
    this.address,
    this.isActive,
    this.url,
    this.status,
    this.lastSeen,
    this.linkedPeerId,
    this.linkedContactId,
  });

  /// Create a NetworkMember from a Contact model
  factory NetworkMember.fromContact(Contact contact) {
    return NetworkMember(
      id: contact.id ?? 0,
      name: contact.name,
      type: contact.type == 'borrower'
          ? NetworkMemberType.borrower
          : NetworkMemberType.library,
      source: NetworkMemberSource.local,
      email: contact.email,
      phone: contact.phone,
      notes: contact.notes,
      address: contact.address,
      isActive: contact.isActive,
    );
  }

  /// Create a NetworkMember from a Peer JSON map
  factory NetworkMember.fromPeer(Map<String, dynamic> peer) {
    final status = peer['status'] as String?;
    return NetworkMember(
      id: peer['id'] as int,
      name: peer['name'] as String,
      type: NetworkMemberType.library,
      source: NetworkMemberSource.network,
      url: peer['url'] as String?,
      status: status ?? 'connected',
      lastSeen: peer['last_seen'] as String?,
    );
  }

  /// Check if this is an online peer
  bool get isOnline =>
      source == NetworkMemberSource.network && status == 'connected';

  /// Check if this is a pending connection request
  bool get isPending =>
      source == NetworkMemberSource.network && status == 'pending';

  /// Check if this local contact can be connected to the network
  bool get canConnect =>
      source == NetworkMemberSource.local && type == NetworkMemberType.library;

  /// Get display status text
  String get displayStatus {
    if (source == NetworkMemberSource.network) {
      switch (status) {
        case 'connected':
          return 'En ligne';
        case 'pending':
          return 'En attente';
        default:
          return 'Hors ligne';
      }
    } else {
      return isActive == true ? 'Actif' : 'Inactif';
    }
  }

  /// Get secondary info for display (email/phone for contacts, URL for peers)
  String get secondaryInfo {
    if (source == NetworkMemberSource.network) {
      return url?.replaceAll('http://', '') ?? '';
    } else {
      return email ?? phone ?? 'Aucune info de contact';
    }
  }
}
