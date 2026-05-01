import 'package:bibliogenius/services/backup_rotation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Anchor every test at a fixed Thursday so weekly bucketing is
  // deterministic regardless of when the test suite runs.
  // Thursday 2026-04-30 12:00 UTC. ISO week starts Mon 2026-04-27.
  final now = DateTime.utc(2026, 4, 30, 12, 0, 0);

  RotationFile autoOn(DateTime ts) => RotationFile(
        name: 'bibliogenius-auto-${_stamp(ts)}.bgbackup',
        timestamp: ts,
      );

  test('empty input returns empty decision', () {
    final result = BackupRotationPolicy.decide([], now: now);
    expect(result.toKeep, isEmpty);
    expect(result.toDelete, isEmpty);
  });

  test('5 recent files: nothing to delete (under daily quota)', () {
    final files = [
      for (var d = 1; d <= 5; d++)
        autoOn(now.subtract(Duration(days: d))),
    ];

    final result = BackupRotationPolicy.decide(files, now: now);

    expect(result.toKeep.length, 5);
    expect(result.toDelete, isEmpty);
  });

  test('12 same-day files: keep top 7 + earliest as week-0 representative', () {
    // 12 archives produced over a single afternoon. Daily rule keeps the 7
    // most recent; the weekly rule promotes the oldest of the day back to
    // "keep" because it is the earliest file in the current ISO week.
    final files = [
      for (var i = 0; i < 12; i++)
        autoOn(now.subtract(Duration(minutes: 5 * i))),
    ];

    final result = BackupRotationPolicy.decide(files, now: now);

    expect(
      result.toKeep.length,
      8,
      reason:
          '7 most-recent (daily) + 1 oldest-of-this-week (weekly w=0) deduped',
    );
    expect(result.toDelete.length, 4);
    // 12 files at minutes 0, 5, .., 55. Top-7 daily covers 0..30.
    // The 5 oldest (35, 40, 45, 50, 55) are deletion candidates EXCEPT the
    // very oldest (55), rescued by the weekly w=0 rule.
    final deletedMinutes = result.toDelete
        .map((f) => now.difference(f.timestamp).inMinutes)
        .toSet();
    expect(deletedMinutes, {35, 40, 45, 50});
    final keptOldest = result.toKeep
        .reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b);
    expect(now.difference(keptOldest.timestamp).inMinutes, 55);
  });

  test(
      '30 files spread across 30 days: daily 7 + weekly representatives '
      '(deduped against daily window)', () {
    // One archive per day for 30 consecutive days. Anchored at Thu 4-30:
    //   ISO week 0  = Mon 4-27 .. Sun 5-03  (covers d=-1, -2, -3)
    //   ISO week 1  = Mon 4-20 .. Sun 4-26  (covers d=-4 .. -10)
    //   ISO week 2  = Mon 4-13 .. Sun 4-19  (covers d=-11 .. -17)
    //   ISO week 3  = Mon 4-06 .. Sun 4-12  (covers d=-18 .. -24)
    // Daily set keeps d=-1 .. -7. Weekly w=0 earliest = d=-3 (already in
    // daily). w=1 earliest = d=-10 (NEW). w=2 = d=-17 (NEW). w=3 = d=-24
    // (NEW). Final keep = 7 + 3 = 10. Delete = 20.
    final files = [
      for (var d = 1; d <= 30; d++)
        autoOn(now.subtract(Duration(days: d))),
    ];

    final result = BackupRotationPolicy.decide(files, now: now);

    expect(result.toKeep.length, 10);
    expect(result.toDelete.length, 20);

    final keptDays = result.toKeep
        .map((f) => now.difference(f.timestamp).inDays)
        .toSet();
    expect(keptDays, {1, 2, 3, 4, 5, 6, 7, 10, 17, 24});
  });

  test('files without bibliogenius-auto- prefix are ignored entirely', () {
    final autoFiles = [
      for (var d = 1; d <= 3; d++) autoOn(now.subtract(Duration(days: d))),
    ];
    final manualFile = RotationFile(
      name: 'my-manual-export.bgbackup',
      timestamp: now.subtract(const Duration(days: 90)),
    );
    final unrelated = RotationFile(
      name: '.DS_Store',
      timestamp: now.subtract(const Duration(days: 5)),
    );

    final result = BackupRotationPolicy.decide(
      [...autoFiles, manualFile, unrelated],
      now: now,
    );

    expect(
      result.toKeep.length + result.toDelete.length,
      3,
      reason: 'only files with the auto prefix should appear in the decision',
    );
    expect(
      [...result.toKeep, ...result.toDelete]
          .every((f) => f.name.startsWith(BackupRotationPolicy.autoPrefix)),
      isTrue,
    );
  });
}

String _stamp(DateTime ts) {
  String two(int v) => v.toString().padLeft(2, '0');
  final u = ts.toUtc();
  return '${u.year}${two(u.month)}${two(u.day)}-${two(u.hour)}${two(u.minute)}';
}
