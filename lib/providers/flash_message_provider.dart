import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Definition of a flash message that can be shown to the user.
class FlashMessageDefinition {
  /// Unique key, also used as SharedPreferences prefix for dismiss state.
  final String key;

  /// i18n key for the message text (used by default layout).
  final String textKey;

  /// Optional i18n key for the action button label (default layout).
  final String? actionTextKey;

  /// Optional GoRouter route to navigate to when the action is tapped (default layout).
  final String? actionRoute;

  /// Optional custom content builder. When provided, replaces the default
  /// text+action layout. Receives (context, dismissCallback).
  final Widget Function(BuildContext context, VoidCallback dismiss)?
  contentBuilder;

  /// Dynamic condition: return true if the flash should be eligible for display.
  final bool Function(BuildContext context) condition;

  /// Routes where this flash should NOT be displayed.
  final List<String>? excludedRoutes;

  /// Routes where this flash should be displayed (null = all routes).
  final List<String>? allowedRoutes;

  /// Optional icon to display instead of the default info_outline.
  final IconData? icon;

  /// When true, the flash bar hides the leading icon badge and gives the
  /// full width to the content. Useful for rich content builders that
  /// provide their own visual elements (e.g. preset cards with icons).
  final bool fullWidthContent;

  /// When false, dismissing hides the flash for the current session only
  /// (no SharedPreferences write). Use for diagnostic warnings about
  /// conditions that can recur, so they resurface on the next launch if
  /// the condition still holds.
  final bool persistDismissal;

  const FlashMessageDefinition({
    required this.key,
    required this.textKey,
    this.actionTextKey,
    this.actionRoute,
    this.contentBuilder,
    required this.condition,
    this.excludedRoutes,
    this.allowedRoutes,
    this.icon,
    this.fullWidthContent = false,
    this.persistDismissal = true,
  });
}

/// Data for a single ephemeral peer connection flash.
/// Not persisted to SharedPreferences - in-memory for the session only.
class EphemeralPeerFlash {
  final int peerId;
  final String peerName;
  final String? peerUrl;
  final String? nodeId;
  final bool hasRelayCredentials;
  final DateTime connectedAt;

  /// True when this is a pending connection request that needs validation.
  /// False (default) for an already-accepted connection.
  final bool isPending;

  const EphemeralPeerFlash({
    required this.peerId,
    required this.peerName,
    this.peerUrl,
    this.nodeId,
    this.hasRelayCredentials = false,
    required this.connectedAt,
    this.isPending = false,
  });

  /// Same peer seen through any of the keys the emitting screens use.
  bool isSamePeerAs(EphemeralPeerFlash other) =>
      other.peerId == peerId ||
      (peerUrl != null && other.peerUrl == peerUrl) ||
      (nodeId != null && other.nodeId == nodeId);
}

/// Peers already announced in this session, under every key they came with.
class _SeenPeers {
  final Set<int> _ids = {};
  final Set<String> _urls = {};
  final Set<String> _nodeIds = {};

  bool contains(EphemeralPeerFlash flash) =>
      _ids.contains(flash.peerId) ||
      (flash.peerUrl != null && _urls.contains(flash.peerUrl)) ||
      (flash.nodeId != null && _nodeIds.contains(flash.nodeId));

  void add(EphemeralPeerFlash flash) {
    _ids.add(flash.peerId);
    if (flash.peerUrl != null) _urls.add(flash.peerUrl!);
    if (flash.nodeId != null) _nodeIds.add(flash.nodeId!);
  }

  void clear() {
    _ids.clear();
    _urls.clear();
    _nodeIds.clear();
  }
}

/// Provider that manages flash messages: registration, dismissal, visibility.
class FlashMessageProvider extends ChangeNotifier {
  final List<FlashMessageDefinition> _definitions = [];
  final Set<String> _dismissed = {};
  bool _loaded = false;
  bool _hasBooks = false;

  /// Whether the library contains at least one book.
  bool get hasBooks => _hasBooks;

  /// Mark that the library now has books (called after first book added).
  void markHasBooks() {
    if (_hasBooks) return;
    _hasBooks = true;
    notifyListeners();
  }

  // -- Ephemeral peer connection flashes --
  static const int maxEphemeralVisible = 3;
  final List<EphemeralPeerFlash> _ephemeralFlashes = [];
  final _shownPending = _SeenPeers();
  final _shownAccepted = _SeenPeers();

  /// Register a flash message definition.
  void register(FlashMessageDefinition definition) {
    // Avoid duplicate registrations
    if (_definitions.any((d) => d.key == definition.key)) return;
    _definitions.add(definition);
    notifyListeners();
  }

  /// Load dismissed flags from SharedPreferences.
  Future<void> loadDismissedFlags() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    for (final def in _definitions) {
      if (prefs.getBool('${def.key}_dismissed') == true) {
        _dismissed.add(def.key);
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Reset all in-memory state (after app reset / prefs.clear()).
  /// Clears dismissed flags so flash messages reappear.
  /// Keeps _loaded = true since we know the state is clean.
  void reset() {
    _dismissed.clear();
    _hasBooks = false;
    _ephemeralFlashes.clear();
    _shownPending.clear();
    _shownAccepted.clear();
    notifyListeners();
  }

  /// Check if a flash message has been dismissed.
  bool isDismissed(String key) => _dismissed.contains(key);

  /// Dismiss a flash message. Persists across launches unless the
  /// definition opted out via `persistDismissal: false` (session-only).
  Future<void> dismiss(String key) async {
    _dismissed.add(key);
    notifyListeners();
    var persist = true;
    for (final def in _definitions) {
      if (def.key == key) {
        persist = def.persistDismissal;
        break;
      }
    }
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${key}_dismissed', true);
  }

  /// Get the list of flash messages visible for the given context and route.
  List<FlashMessageDefinition> getVisibleFlashes(
    BuildContext context,
    String currentRoute,
  ) {
    if (!_loaded) return [];
    return _definitions.where((def) {
      // Already dismissed
      if (_dismissed.contains(def.key)) return false;

      // Route filtering
      if (def.excludedRoutes != null) {
        for (final route in def.excludedRoutes!) {
          if (currentRoute.startsWith(route)) return false;
        }
      }
      if (def.allowedRoutes != null) {
        bool allowed = false;
        for (final route in def.allowedRoutes!) {
          if (currentRoute.startsWith(route)) {
            allowed = true;
            break;
          }
        }
        if (!allowed) return false;
      }

      // Dynamic condition
      if (!def.condition(context)) return false;

      return true;
    }).toList();
  }

  // -- Ephemeral peer flash methods --

  /// Add an ephemeral flash for a newly connected peer.
  /// Deduplicates by peerId, peerUrl, and nodeId within the session.
  /// This prevents duplicates when the same peer is detected by both
  /// the outgoing connection screen (url.hashCode) and the incoming
  /// detection poll (DB id).
  ///
  /// An accepted connection is only shown when [showAccepted] is set: the
  /// plain "paired with" banner was dropped as noise, and comes back only
  /// when it carries something to do (the contact card invitation). It then
  /// replaces the pending banner of the same peer rather than stacking on it.
  void addEphemeralPeer(EphemeralPeerFlash flash, {bool showAccepted = false}) {
    if (flash.isPending) {
      if (_shownPending.contains(flash) || _shownAccepted.contains(flash)) {
        return;
      }
      _shownPending.add(flash);
    } else {
      if (!showAccepted || _shownAccepted.contains(flash)) return;
      _shownAccepted.add(flash);
      _shownPending.add(flash);
      _ephemeralFlashes.removeWhere(flash.isSamePeerAs);
    }
    _ephemeralFlashes.insert(0, flash); // newest first
    notifyListeners();
  }

  /// Dismiss a single ephemeral flash by peerId.
  void dismissEphemeral(int peerId) {
    _ephemeralFlashes.removeWhere((f) => f.peerId == peerId);
    notifyListeners();
  }

  /// Dismiss all ephemeral flashes.
  void dismissAllEphemeral() {
    _ephemeralFlashes.clear();
    notifyListeners();
  }

  /// The up-to-3 flashes shown as bars.
  List<EphemeralPeerFlash> get visibleEphemeralFlashes =>
      _ephemeralFlashes.take(maxEphemeralVisible).toList();

  /// All flashes (for the "see more" dialog).
  List<EphemeralPeerFlash> get allEphemeralFlashes =>
      List.unmodifiable(_ephemeralFlashes);

  /// Whether there are more ephemerals than the visible limit.
  bool get hasEphemeralOverflow =>
      _ephemeralFlashes.length > maxEphemeralVisible;

  /// Count of hidden ephemeral flashes.
  int get ephemeralOverflowCount =>
      _ephemeralFlashes.length > maxEphemeralVisible
      ? _ephemeralFlashes.length - maxEphemeralVisible
      : 0;
}
