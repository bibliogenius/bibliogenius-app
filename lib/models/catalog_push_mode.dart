// How the catalog is pushed to the hub (ADR-072 D1, D8).
//
// Pure decision over the local directory config and the followers list,
// kept out of the provider so it can be tested without a hub or an FFI.

import 'hub_directory.dart';

/// What the hub stores for this library's catalog.
enum CatalogPushMode {
  /// The clear JSON payload every hub reader can parse.
  clear,

  /// A ciphertext under the library's catalog key, opened by each reader
  /// with the wrap it holds on its follow row.
  encrypted,
}

/// First app version that reads an encrypted catalog. An owner encrypts
/// only when every current reader runs at least this version (D8); the
/// value must be the exact version that ships the reader, never lower.
const String encryptedCatalogMinAppVersion = '1.3.0';

/// Decides the push mode.
///
/// A public library (listed without approval) stays in clear: there is
/// nobody to encrypt for. Otherwise the catalog is encrypted only when every
/// reader can open it: a published X25519 key to wrap for, and an app
/// version at or above [minAppVersion]. An unknown version is read as too
/// old. Pending, rejected and blocked follows are not readers, and neither
/// is an active follower the owner took off its readers list (an ex-peer
/// still following gets no wrap, so it does not hold the others back), nor
/// one whose key changed under its pin (a reinstall, or a key substituted
/// by the hub): it gets no wrap until the owner approves or pairs it again,
/// and the catalog stays encrypted for the others. An active follower the
/// list never held keeps the catalog in clear rather than being locked out.
CatalogPushMode decideCatalogPushMode({
  required bool isListed,
  required bool requiresApproval,
  required List<HubFollow> followers,
  String minAppVersion = encryptedCatalogMinAppVersion,
}) {
  if (isListed && !requiresApproval) return CatalogPushMode.clear;
  for (final f in followers) {
    if (!f.isActive) continue;
    // Not an authorised reader: off the list, or published another key
    // than the pinned one. Its build is not consulted either.
    if (f.catalogReaderStatus == 'not_reader' ||
        f.catalogReaderStatus == 'key_mismatch') {
      continue;
    }
    // An active follower the owner's list never held (approved without a
    // key, seen only while the library was public): encrypting would lock
    // it out.
    if (f.catalogReaderStatus == 'unknown') return CatalogPushMode.clear;
    if (!followerCanReadEncryptedCatalog(f, minAppVersion: minAppVersion)) {
      return CatalogPushMode.clear;
    }
  }
  return CatalogPushMode.encrypted;
}

/// Whether one follower could open an encrypted catalog: it has a key to
/// wrap for and a build that knows the format.
bool followerCanReadEncryptedCatalog(
  HubFollow follower, {
  String minAppVersion = encryptedCatalogMinAppVersion,
}) {
  final key = follower.followerX25519PublicKey;
  if (key == null || key.isEmpty) return false;
  final version = follower.followerAppVersion;
  if (version == null || version.isEmpty) return false;
  return compareAppVersions(version, minAppVersion) >= 0;
}

/// Compares two app versions of the shape `major.minor.patch+build`, as
/// `DeviceService.getAppVersion` publishes them. The numeric core decides;
/// the build number breaks a tie only when both carry one. A core that
/// does not parse compares as the lowest version there is.
int compareAppVersions(String a, String b) {
  final pa = _parseVersion(a);
  final pb = _parseVersion(b);
  if (pa == null || pb == null) {
    if (pa == null && pb == null) return 0;
    return pa == null ? -1 : 1;
  }
  for (var i = 0; i < 3; i++) {
    final d = pa.core[i].compareTo(pb.core[i]);
    if (d != 0) return d;
  }
  final ba = pa.build;
  final bb = pb.build;
  if (ba == null || bb == null) return 0;
  return ba.compareTo(bb);
}

class _ParsedVersion {
  final List<int> core;
  final int? build;
  const _ParsedVersion(this.core, this.build);
}

_ParsedVersion? _parseVersion(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final plus = trimmed.indexOf('+');
  final corePart = plus < 0 ? trimmed : trimmed.substring(0, plus);
  final buildPart = plus < 0 ? null : trimmed.substring(plus + 1);
  final parts = corePart.split('.');
  if (parts.isEmpty || parts.length > 3) return null;
  final core = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    core.add(n);
  }
  while (core.length < 3) {
    core.add(0);
  }
  final build = buildPart == null ? null : int.tryParse(buildPart);
  return _ParsedVersion(core, build);
}
