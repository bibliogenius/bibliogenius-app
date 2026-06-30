import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Drives automatic account-sync cycles in the background (ADR-046 / account
/// E2EE sync). Today a sync only happens when the user taps "Sync now"; this
/// scheduler adds two triggers so devices converge on their own:
///
/// - a **periodic** timer ([tickInterval]), and
/// - an **on-resume** catch-up (iOS suspends the timer in the background, so a
///   foreground resume re-checks), gated by a short floor so rapid app-switches
///   do not spin the sync repeatedly.
///
/// The deliberately-dropped third trigger (event-debounced "mark dirty" on every
/// write path) buys only lower latency: the engine pushes just the delta since
/// the last cursor and is idempotent, so periodic + on-resume converge every
/// entity uniformly without instrumenting dozens of write sites.
///
/// Design constraints honoured here:
/// - **Inert unless the build can sync.** [capable] reflects the `account_sync`
///   Cargo feature; on default builds the scheduler attaches no timer or
///   observer at all (the FFI data leg is a no-op there, so a periodic network
///   refresh would be pure waste).
/// - **Silent.** The tick goes through [runSync] (the provider's quiet
///   `autoSyncTick`), which never surfaces a spinner or a network error.
/// - **Gentle on the single-connection pool.** The account-sync build pins the
///   DB to one connection, so a modest cadence avoids contention with
///   foreground work; the in-flight guard lives in the provider.
/// - **Backoff.** After a failed tick the on-resume floor widens to
///   [tickInterval], so a down hub is not retried faster than the periodic
///   cadence on repeated resumes.
///
/// All side effects are injected so unit tests can drive the scheduler without
/// FFI or a real provider. Production callers use
/// [AccountSyncScheduler.production].
class AccountSyncScheduler with WidgetsBindingObserver {
  /// Periodic sync cadence. Fresher than the daily auto-backup but still gentle
  /// on the pinned single connection.
  static const Duration tickInterval = Duration(minutes: 15);

  /// Minimum gap before an app-resume may trigger a sync, so flipping the app in
  /// and out does not run back-to-back cycles. Widens to [tickInterval] after a
  /// failed tick (backoff for a down hub).
  static const Duration resumeFloor = Duration(minutes: 2);

  final Future<bool> Function() _capable;
  final Future<bool> Function() _runSync;
  final Future<void> Function() _refreshStatus;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _initialized = false;
  bool _observerAttached = false;
  bool _isCapable = false;
  bool _lastTickFailed = false;
  DateTime? _lastAttemptAt;

  AccountSyncScheduler({
    required Future<bool> Function() capable,
    required Future<bool> Function() runSync,
    required Future<void> Function() refreshStatus,
    required DateTime Function() clock,
  })  : _capable = capable,
        _runSync = runSync,
        _refreshStatus = refreshStatus,
        _clock = clock;

  /// Production wiring: capability + sync via FFI/provider, real clock.
  factory AccountSyncScheduler.production({
    required Future<bool> Function() capable,
    required Future<bool> Function() runSync,
    required Future<void> Function() refreshStatus,
  }) {
    return AccountSyncScheduler(
      capable: capable,
      runSync: runSync,
      refreshStatus: refreshStatus,
      clock: DateTime.now,
    );
  }

  // -- Test/inspection seams --------------------------------------------------

  @visibleForTesting
  bool get isCapable => _isCapable;

  @visibleForTesting
  bool get timerActive => _timer != null;

  // -- Lifecycle --------------------------------------------------------------

  /// Probe the build capability; if this build can sync, register the lifecycle
  /// observer, start the periodic timer, load the signed-in status once, and run
  /// an initial catch-up tick. On default builds it returns having done nothing,
  /// leaving the scheduler fully inert. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _isCapable = await _capable();
    } catch (e) {
      debugPrint('AccountSyncScheduler capability probe failed: $e');
      _isCapable = false;
    }
    if (!_isCapable) return;
    _attachObserver();
    _startTimer();
    // Load the cached signed-in status so the first tick can self-gate, then
    // attempt a catch-up sync (no-op if not enrolled).
    await _refreshStatus();
    await _tick(_Trigger.boot);
  }

  /// Resume hook: the periodic timer is suspended while backgrounded, so a
  /// foreground resume re-checks. Gated by the resume floor so quick app
  /// switches do not run repeated cycles.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || !_isCapable) return;
    if (state != AppLifecycleState.resumed) return;
    unawaited(_tick(_Trigger.resume));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
  }

  // -- Internals --------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => _tick(_Trigger.periodic));
  }

  void _attachObserver() {
    if (_observerAttached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (e) {
      // Pure-dart contexts without an initialized binding (defensive).
      debugPrint('AccountSyncScheduler observer attach skipped: $e');
    }
  }

  Future<void> _tick(_Trigger trigger) async {
    if (!_isCapable) return;

    // Resume can fire arbitrarily often; gate it behind a floor (widened after a
    // failure as a simple backoff). The periodic timer fires at exactly
    // [tickInterval] and the boot tick is one-shot, so neither needs the floor.
    if (trigger == _Trigger.resume) {
      final last = _lastAttemptAt;
      if (last != null) {
        final floor = _lastTickFailed ? tickInterval : resumeFloor;
        if (_clock().difference(last) < floor) return;
      }
    }

    _lastAttemptAt = _clock();
    try {
      final ran = await _runSync();
      _lastTickFailed = !ran;
    } catch (e) {
      // runSync is the provider's quiet tick and should not throw, but never let
      // a stray error escape the scheduler.
      debugPrint('AccountSyncScheduler tick error: $e');
      _lastTickFailed = true;
    }
  }
}

enum _Trigger { boot, periodic, resume }
