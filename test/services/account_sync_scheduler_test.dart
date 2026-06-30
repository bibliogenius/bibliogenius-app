import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/account_sync_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A controllable clock so resume-floor / backoff timing is deterministic.
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime.utc(2026, 6, 30, 12, 0, 0);
  });

  AccountSyncScheduler build({
    required bool capable,
    required Future<bool> Function() runSync,
    int Function()? refreshCount,
  }) {
    var refreshes = 0;
    final s = AccountSyncScheduler(
      capable: () async => capable,
      runSync: runSync,
      refreshStatus: () async {
        refreshes++;
      },
      clock: clock,
    );
    return s;
  }

  test('stays fully inert on a non-capable build', () async {
    var runs = 0;
    final s = build(
      capable: false,
      runSync: () async {
        runs++;
        return true;
      },
    );
    await s.initialize();

    expect(s.isCapable, isFalse);
    expect(s.timerActive, isFalse, reason: 'no timer on a non-capable build');
    expect(runs, 0, reason: 'no sync attempted when the build cannot sync');
    s.dispose();
  });

  test('capable build runs an initial catch-up tick and starts the timer',
      () async {
    var runs = 0;
    final s = build(
      capable: true,
      runSync: () async {
        runs++;
        return true;
      },
    );
    await s.initialize();

    expect(s.isCapable, isTrue);
    expect(s.timerActive, isTrue);
    expect(runs, 1, reason: 'boot tick runs once');
    s.dispose();
    expect(s.timerActive, isFalse, reason: 'dispose cancels the timer');
  });

  test('a resume within the floor is skipped, then runs once past it',
      () async {
    var runs = 0;
    final s = build(
      capable: true,
      runSync: () async {
        runs++;
        return true;
      },
    );
    await s.initialize(); // boot tick at 12:00 -> runs == 1
    expect(runs, 1);

    // Resume immediately: within the 2-minute floor -> skipped.
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1, reason: 'resume within the floor is ignored');

    // Past the floor: resume triggers a sync.
    now = now.add(const Duration(minutes: 3));
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 2, reason: 'resume past the floor runs a cycle');
    s.dispose();
  });

  test('a failed tick widens the resume floor to the periodic interval',
      () async {
    var runs = 0;
    final s = build(
      capable: true,
      // Always "fails" (hub unreachable): returns false.
      runSync: () async {
        runs++;
        return false;
      },
    );
    await s.initialize(); // boot tick fails at 12:00 -> runs == 1
    expect(runs, 1);

    // 3 minutes later: past the normal 2-min floor, but the failure widened it
    // to 15 min, so a resume is still skipped (backoff, don't hammer a down hub).
    now = now.add(const Duration(minutes: 3));
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1, reason: 'resume is held off after a failure');

    // Past the widened floor: it retries.
    now = now.add(const Duration(minutes: 13)); // 16 min since boot
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 2, reason: 'retry allowed once the widened floor elapses');
    s.dispose();
  });

  test('resume is ignored before initialize and on non-capable builds',
      () async {
    var runs = 0;
    final s = build(
      capable: false,
      runSync: () async {
        runs++;
        return true;
      },
    );
    // Before initialize: ignored.
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 0);

    await s.initialize(); // non-capable -> inert
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 0);
    s.dispose();
  });
}
