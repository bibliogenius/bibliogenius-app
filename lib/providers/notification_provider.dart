import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' show FrbNotification;

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

  List<FrbNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  String? get activeCategory => _activeCategory;
  bool get isLoading => _isLoading;

  /// Initialize: prune old entries, load unread count, start polling.
  Future<void> init() async {
    await _ffi.notificationsPrune();
    await refreshUnreadCount();
    // Poll unread count every 30s (lightweight query)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshUnreadCount(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Refresh just the unread badge count (cheap).
  Future<void> refreshUnreadCount() async {
    final count = await _ffi.notificationsUnreadCount();
    if (count != _unreadCount) {
      _unreadCount = count;
      notifyListeners();
    }
  }

  /// Load notifications (full list), optionally filtered by category.
  Future<void> loadNotifications({String? category}) async {
    _isLoading = true;
    _activeCategory = category;
    notifyListeners();

    _notifications = await _ffi.notificationsList(
      category: category,
      limit: 100,
    );

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
