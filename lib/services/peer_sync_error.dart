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
String? peerSyncErrorCode(Object error) => _syncErrorField(error, 'code');

/// The `error` message of a failed sync answer from the local backend, or
/// null when the body carries none. It tells apart the failures that all
/// answer 502 (peer offline, peer error, another library at the address...).
String? peerSyncErrorMessage(Object error) => _syncErrorField(error, 'error');

/// [error] for a debug log line, followed by the backend `error` message
/// when the answer carries one. Only that field is added, never the body.
String describePeerSyncErrorForLog(Object error) {
  final message = peerSyncErrorMessage(error);
  return message == null ? '$error' : '$error (backend: $message)';
}

String? _syncErrorField(Object error, String key) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final value = data[key];
  return value is String ? value : null;
}
