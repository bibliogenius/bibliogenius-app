import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/frb.dart'
    show FrbProfileChangedEvent, subscribeProfileChanges, tryPeerAvatarPull;

/// App-level listener for peer profile changes (ADR-025).
///
/// Subscribes once to the Rust `profile_changed` FRB stream. Whenever a
/// peer edits their avatar (or future profile fields), the Rust relay
/// poller emits an event on this stream, and the service calls
/// [tryPeerAvatarPull] to refresh the peer's cached avatar over E2EE.
///
/// Avatars are ambient UI — they appear on the network screen, peer book
/// lists, profile sheets, borrow dialogs, etc. Subscribing app-wide
/// guarantees the cache stays fresh regardless of which screen the user
/// happens to have open when the nudge arrives.
class AvatarSyncService {
  StreamSubscription<FrbProfileChangedEvent>? _sub;
  bool _started = false;

  /// Start listening. Safe to call multiple times (idempotent).
  /// Requires the FRB bridge to have been initialised (FFI mode).
  void start() {
    if (_started) return;
    _started = true;

    _sub = subscribeProfileChanges().listen(
      (FrbProfileChangedEvent event) async {
        if (event.peerId <= 0) return;
        debugPrint(
          'AvatarSync: profile_changed from peer ${event.peerId} '
          '(changed=${event.changed}), pulling avatar',
        );
        try {
          final changed = await tryPeerAvatarPull(peerId: event.peerId);
          debugPrint(
            'AvatarSync: peer ${event.peerId} pull result changed=$changed',
          );
        } catch (e) {
          debugPrint('AvatarSync: peer ${event.peerId} pull error: $e');
        }
      },
      onError: (Object e) =>
          debugPrint('AvatarSync: profile change stream error: $e'),
      cancelOnError: false,
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
