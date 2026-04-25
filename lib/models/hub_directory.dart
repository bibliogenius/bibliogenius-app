// Models for the public library directory (ADR-015).
//
// Plain Dart data classes that mirror the Rust FFI types
// (FrbDirectoryConfig, FrbHubProfile, FrbHubFollow) without coupling
// the rest of the app to the generated flutter_rust_bridge types.

import '../src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// DirectoryConfig
// ---------------------------------------------------------------------------

/// Local hub directory configuration stored in SQLite (singleton row).
class DirectoryConfig {
  final String nodeId;
  final bool isListed;
  final bool requiresApproval;
  final String acceptFrom;
  final bool allowBorrowing;

  const DirectoryConfig({
    required this.nodeId,
    required this.isListed,
    required this.requiresApproval,
    required this.acceptFrom,
    required this.allowBorrowing,
  });

  factory DirectoryConfig.fromFrb(frb.FrbDirectoryConfig f) => DirectoryConfig(
        nodeId: f.nodeId,
        isListed: f.isListed,
        requiresApproval: f.requiresApproval,
        acceptFrom: f.acceptFrom,
        allowBorrowing: f.allowBorrowing,
      );
}

// ---------------------------------------------------------------------------
// HubProfile
// ---------------------------------------------------------------------------

/// A library profile from the public hub directory.
class HubProfile {
  final String nodeId;
  final String displayName;
  final String? description;
  final int bookCount;
  final String? locationCountry;

  /// GeoNames id of the city the publishing library opted to share
  /// (ADR-035). Resolve to a [CityRecord] via `CityRepository.lookupById`
  /// (passing [locationCountry] so the lazy download targets the right
  /// country file). `null` means the publisher did not opt in.
  final int? locationCityId;
  final bool requiresApproval;
  final bool? allowBorrowing;
  final String? lastSeenAt;
  final String? x25519PublicKey;
  final String? website;
  final String? deviceModel;
  final String? deviceFingerprint;
  final String? appVersion;
  final String? avatarConfig;

  const HubProfile({
    required this.nodeId,
    required this.displayName,
    this.description,
    required this.bookCount,
    this.locationCountry,
    this.locationCityId,
    required this.requiresApproval,
    this.allowBorrowing,
    this.lastSeenAt,
    this.x25519PublicKey,
    this.website,
    this.deviceModel,
    this.deviceFingerprint,
    this.appVersion,
    this.avatarConfig,
  });

  factory HubProfile.fromFrb(frb.FrbHubProfile f) => HubProfile(
        nodeId: f.nodeId,
        displayName: f.displayName,
        description: f.description,
        bookCount: f.bookCount,
        locationCountry: f.locationCountry,
        locationCityId: f.locationCityId,
        requiresApproval: f.requiresApproval,
        allowBorrowing: f.allowBorrowing,
        lastSeenAt: f.lastSeenAt,
        x25519PublicKey: f.x25519PublicKey,
        website: f.website,
        deviceModel: f.deviceModel,
        deviceFingerprint: f.deviceFingerprint,
        appVersion: f.appVersion,
        avatarConfig: f.avatarConfig,
      );
}

// ---------------------------------------------------------------------------
// HubFollow
// ---------------------------------------------------------------------------

/// A follow relationship between two libraries in the hub directory.
class HubFollow {
  final int id;
  final String followerNodeId;
  final String followedNodeId;

  /// One of: "pending", "active", "rejected", "blocked"
  final String status;
  final String createdAt;
  final String? resolvedAt;

  /// Display name of the follower (enriched by the hub for pending requests).
  final String? followerDisplayName;

  /// E2EE sealed blob: followed library's contact info, encrypted for this follower.
  final String? encryptedContact;

  /// X25519 public key of the follower (for encrypting contact info).
  final String? followerX25519PublicKey;

  const HubFollow({
    required this.id,
    required this.followerNodeId,
    required this.followedNodeId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.followerDisplayName,
    this.encryptedContact,
    this.followerX25519PublicKey,
  });

  factory HubFollow.fromFrb(frb.FrbHubFollow f) => HubFollow(
        id: f.id,
        followerNodeId: f.followerNodeId,
        followedNodeId: f.followedNodeId,
        status: f.status,
        createdAt: f.createdAt,
        resolvedAt: f.resolvedAt,
        followerDisplayName: f.followerDisplayName,
        encryptedContact: f.encryptedContact,
        followerX25519PublicKey: f.followerX25519PublicKey,
      );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
}
