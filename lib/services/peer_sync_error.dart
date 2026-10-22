import 'package:dio/dio.dart';

/// The `code` the local backend sets on a failed peer sync when the peer
/// answers with the same library uuid but another signing key (a reinstall
/// that lost its keys). Mirrors `no_plaintext_fallback_error` in the Rust
/// core.
const peerKeysChangedCode = 'peer_keys_changed';

/// Thrown by `ApiService.syncPeer` when the peer answers under new keys: the
/// pairing cannot work any more, and the owner must remove the peer and scan
/// its QR code again.
class PeerKeysChangedException implements Exception {
  const PeerKeysChangedException();

  @override
  String toString() => 'PeerKeysChangedException: $peerKeysChangedCode';
}

/// The `code` of a failed sync answer from the local backend, or null when
/// the failure names none.
String? peerSyncErrorCode(Object error) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final code = data['code'];
  return code is String ? code : null;
}
