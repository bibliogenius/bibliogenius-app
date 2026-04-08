import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' show FrbNotification, FrbNudgeEvent, subscribeRelayNudges;

/// Provider for the activity feed (notifications).
///
/// Manages unread count badge, list pagination, filtering by category,
/// and dismiss/mark-read actions.
class NotificationProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  List<FrbNotification> _notifications = [];
  int _unreadCount = 0;
  String? _activeCategory; // null = all
  bool _isLoading = false;
  Timer? _pollTimer;
  StreamSubscription<FrbNudgeEvent>? _nudgeSub;

  List<FrbNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  String? get activeCategory => _activeCategory;
  bool get isLoading => _isLoading;

  /// Initialize: prune old entries, load unread count, start polling and
  /// subscribe to the relay nudge stream for instant refreshes (ADR-017
  /// Phase 3a). The 30s timer remains as a fallback while the stream is
  /// being soak-tested in production.
  Future<void> init() async {
    await _ffi.notificationsPrune();
    await refreshUnreadCount();
    // Poll unread count every 30s (lightweight query, fallback safety net)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshUnreadCount(),
    );
    _subscribeNudgeStream();
  }

  /// Subscribe to the FFI relay nudge stream. Each event triggers an
  /// immediate badge refresh, replacing the 30s polling latency with a
  /// near-instant update (1 to 3 seconds end to end).
  void _subscribeNudgeStream() {
    _nudgeSub?.cancel();
    try {
      _nudgeSub = subscribeRelayNudges().listen(
        _onNudgeEvent,
        onError: (Object e) {
          debugPrint('NotificationProvider: nudge stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('NotificationProvider: failed to subscribe to nudge stream: $e');
    }
  }

  void _onNudgeEvent(FrbNudgeEvent event) {
    // Fire-and-forget: refreshUnreadCount handles its own state updates.
    refreshUnreadCount();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nudgeSub?.cancel();
    super.dispose();
  }

  /// Refresh just the unread badge count (cheap).
  /// If all notification categories are disabled, forces count to 0.
  Future<void> refreshUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final globalEnabled = prefs.getBool('notificationsEnabled') ?? true;
    final anyEnabled = globalEnabled &&
        ((prefs.getBool('notifConnectionsEnabled') ?? true) ||
         (prefs.getBool('notifLoansEnabled') ?? true) ||
         (prefs.getBool('notifDiscoveriesEnabled') ?? true));

    final count = anyEnabled ? await _ffi.notificationsUnreadCount() : 0;
    if (count != _unreadCount) {
      _unreadCount = count;
      notifyListeners();
    }
  }

  /// Load notifications (full list), optionally filtered by category.
  /// Respects per-category toggles from settings.
  Future<void> loadNotifications({String? category}) async {
    _isLoading = true;
    _activeCategory = category;
    notifyListeners();

    _notifications = await _ffi.notificationsList(
      category: category,
      limit: 100,
    );

    // Filter out disabled categories
    final prefs = await SharedPreferences.getInstance();
    final enabledCategories = <String>{
      if (prefs.getBool('notifConnectionsEnabled') ?? true) 'connections',
      if (prefs.getBool('notifLoansEnabled') ?? true) 'loans',
      if (prefs.getBool('notifDiscoveriesEnabled') ?? true) 'discoveries',
    };
    _notifications = _notifications
        .where((n) => enabledCategories.contains(n.category))
        .toList();

    _isLoading = false;
    notifyListeners();
  }

  /// Set active filter and reload.
  Future<void> filterByCategory(String? category) async {
    await loadNotifications(category: category);
  }

  /// Mark a single notification as read.
  Future<void> markRead(int id) async {
    await _ffi.notificationsMarkRead(id);
    // Update local state
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx >= 0 && _notifications[idx].readAt == null) {
      _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
    }
    // Reload to get fresh data
    await loadNotifications(category: _activeCategory);
    notifyListeners();
  }

  /// Mark all as read.
  Future<void> markAllRead() async {
    await _ffi.notificationsMarkAllRead();
    _unreadCount = 0;
    await loadNotifications(category: _activeCategory);
    notifyListeners();
  }

  /// Clear (hard delete) all notifications.
  Future<void> clearAll() async {
    await _ffi.notificationsDismissAll();
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();
  }

  /// Dismiss (hard delete) a notification.
  Future<void> dismiss(int id) async {
    final n = _notifications.firstWhere((n) => n.id == id,
        orElse: () => _notifications.first);
    if (n.readAt == null) {
      _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
    }
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
    // Delete in background
    await _ffi.notificationsDismiss(id);
  }
}
