import 'dart:convert';

import '../models/avatar_config.dart';
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
  final String? firstName;
  final NetworkMemberType type;
  final NetworkMemberSource source;

  // Contact-specific fields (null for network peers)
  final String? email;
  final String? phone;
  final String? notes;
  final String? address;
  final String? streetAddress;
  final String? postalCode;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;
  final bool? isActive;

  // Peer-specific fields (null for local contacts)
  final String? url;
  final String? status; // 'connected', 'pending', 'offline'
  final String? lastSeen;
  /// Whether E2EE key exchange is complete with this peer
  final bool keyExchangeDone;
  /// UUID of the peer's library (for disambiguation)
  final String? libraryUuid;
  /// Whether this peer has relay credentials (reachable via hub)
  final bool hasRelayCredentials;

  /// User-defined display name (overrides name in the UI)
  final String? customDisplayName;

  /// Avatar configuration from the remote peer's profile (JSON)
  final AvatarConfig? avatarConfig;

  // V4 Future: Association link
  final int? linkedPeerId;
  final int? linkedContactId;

  const NetworkMember({
    required this.id,
    required this.name,
    this.firstName,
    required this.type,
    required this.source,
    this.email,
    this.phone,
    this.notes,
    this.address,
    this.streetAddress,
    this.postalCode,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
    this.isActive,
    this.url,
    this.status,
    this.lastSeen,
    this.keyExchangeDone = false,
    this.libraryUuid,
    this.hasRelayCredentials = false,
    this.customDisplayName,
    this.avatarConfig,
    this.linkedPeerId,
    this.linkedContactId,
  });

  /// Get display name: always the original name (never overridden by caption).
  String get displayName {
    if (firstName != null && firstName!.isNotEmpty) {
      return '$firstName $name';
    }
    return name;
  }

  /// User-defined caption to distinguish contacts with the same name.
  String? get caption => customDisplayName;

  /// Return a copy with an updated caption.
  NetworkMember withCaption(String? newCaption) => NetworkMember(
        id: id,
        name: name,
        firstName: firstName,
        type: type,
        source: source,
        email: email,
        phone: phone,
        notes: notes,
        address: address,
        streetAddress: streetAddress,
        postalCode: postalCode,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
        isActive: isActive,
        url: url,
        status: status,
        lastSeen: lastSeen,
        keyExchangeDone: keyExchangeDone,
        libraryUuid: libraryUuid,
        hasRelayCredentials: hasRelayCredentials,
        customDisplayName: newCaption,
        avatarConfig: avatarConfig,
        linkedPeerId: linkedPeerId,
        linkedContactId: linkedContactId,
      );

  /// Create a NetworkMember from a Contact model
  factory NetworkMember.fromContact(Contact contact) {
    return NetworkMember(
      id: contact.id ?? 0,
      name: contact.name,
      firstName: contact.firstName,
      type: contact.type == 'borrower'
          ? NetworkMemberType.borrower
          : NetworkMemberType.library,
      source: NetworkMemberSource.local,
      email: contact.email,
      phone: contact.phone,
      notes: contact.notes,
      address: contact.address,
      streetAddress: contact.streetAddress,
      postalCode: contact.postalCode,
      city: contact.city,
      country: contact.country,
      latitude: contact.latitude,
      longitude: contact.longitude,
      isActive: contact.isActive,
    );
  }

  /// Create a NetworkMember from a Peer JSON map
  factory NetworkMember.fromPeer(Map<String, dynamic> peer) {
    // Prefer connection_status over status for more accurate state
    final connectionStatus = peer['connection_status'] as String?;
    final status = peer['status'] as String?;
    final derivedStatus = connectionStatus == 'pending'
        ? 'pending'
        : (status ?? 'connected');
    return NetworkMember(
      id: peer['id'] as int,
      name: peer['name'] as String,
      type: NetworkMemberType.library,
      source: NetworkMemberSource.network,
      url: peer['url'] as String?,
      status: derivedStatus,
      lastSeen: peer['last_seen'] as String?,
      keyExchangeDone: peer['key_exchange_done'] == true ||
          peer['key_exchange_done'] == 1,
      libraryUuid: peer['library_uuid'] as String?,
      hasRelayCredentials: (peer['relay_url'] as String?)?.isNotEmpty == true &&
          (peer['mailbox_id'] as String?)?.isNotEmpty == true &&
          (peer['relay_write_token'] as String?)?.isNotEmpty == true,
      customDisplayName: peer['display_name'] as String?,
      avatarConfig: _parseAvatarConfig(peer['avatar_config']),
    );
  }

  static AvatarConfig? _parseAvatarConfig(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is String) {
        return AvatarConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      if (raw is Map<String, dynamic>) {
        return AvatarConfig.fromJson(raw);
      }
    } catch (_) {}
    return null;
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
          return '';
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

  /// Convert NetworkMember back to Contact (only works for local contacts)
  Contact toContact() {
    return Contact(
      id: id,
      type: type == NetworkMemberType.borrower ? 'borrower' : 'library',
      name: name,
      firstName: firstName,
      email: email,
      phone: phone,
      address: address,
      streetAddress: streetAddress,
      postalCode: postalCode,
      city: city,
      country: country,
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      libraryOwnerId: null, // Resolved by backend
      isActive: isActive ?? true,
    );
  }
}
