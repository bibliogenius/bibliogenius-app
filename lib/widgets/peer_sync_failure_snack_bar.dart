import 'package:flutter/material.dart';

import '../services/peer_sync_error.dart';
import '../services/translation_service.dart';

/// The snack bar of a manual peer sync that failed. A peer the hub confirmed
/// has new keys cannot be synced again until it is paired again: the bar
/// says what to do, and stays long enough to be read.
SnackBar peerSyncFailureSnackBar(BuildContext context, Object error) {
  final keysChanged = error is PeerKeysChangedException;
  return SnackBar(
    content: Text(
      TranslationService.translate(
        context,
        keysChanged ? 'peer_keys_changed' : 'sync_failed',
      ),
    ),
    backgroundColor: Colors.orange,
    duration: keysChanged
        ? const Duration(seconds: 10)
        : const Duration(milliseconds: 4000),
  );
}
