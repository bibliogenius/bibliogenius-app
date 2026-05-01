/// Pure rotation policy for `.bgbackup` auto-archives (ADR-037 §6).
///
/// Decides which auto-backup files to keep and which to delete given the
/// current set on disk, anchored at a caller-supplied "now". Pure: no I/O,
/// no clock access, no FFI. Lives outside the scheduler so it can be unit
/// tested with a synthetic file set without spinning up the full backup
/// pipeline.
///
/// Rules:
///  - Only files whose name starts with [autoPrefix] are considered. Manual
///    backups dropped in the same directory are silently ignored (they
///    appear in neither output list).
///  - Keep the [dailyKeep] most recent auto-backups.
///  - For each of the last [weeklyKeep] ISO weeks (anchored at `now`), keep
///    the earliest auto-backup that falls in that week. The "first
///    auto-backup of each of the last N weeks" is the slow-decay tail.
///  - A file kept by both rules is kept once (no double counting).
///  - Anything left over is `toDelete`.
library;

const String autoBackupFilePrefix = 'bibliogenius-auto-';

class RotationFile {
  final String name;
  final DateTime timestamp;

  const RotationFile({required this.name, required this.timestamp});
}

class BackupRotationDecision {
  final List<RotationFile> toKeep;
  final List<RotationFile> toDelete;

  const BackupRotationDecision({
    required this.toKeep,
    required this.toDelete,
  });
}

class BackupRotationPolicy {
  static const String autoPrefix = autoBackupFilePrefix;
  static const int dailyKeep = 7;
  static const int weeklyKeep = 4;

  /// Decide the rotation for `files`, anchored at `now`. Files without
  /// [autoPrefix] are dropped: the caller never sees them in either output
  /// and therefore never deletes them.
  static BackupRotationDecision decide(
    List<RotationFile> files, {
    required DateTime now,
  }) {
    final autos = files
        .where((f) => f.name.startsWith(autoPrefix))
        .toList(growable: false);
    if (autos.isEmpty) {
      return const BackupRotationDecision(toKeep: [], toDelete: []);
    }

    final sortedDesc = [...autos]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final keepNames = <String>{};
    for (var i = 0; i < sortedDesc.length && i < dailyKeep; i++) {
      keepNames.add(sortedDesc[i].name);
    }

    // Anchor week boundaries at `now` in UTC. Filenames are minted in UTC
    // (see scheduler), so anchoring locally would cross-pollinate the
    // bucketing across timezone boundaries. UTC keeps it deterministic.
    final nowUtc = now.toUtc();
    final nowMidnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    // ISO weekday: 1=Mon..7=Sun. weekday-1 days before today = Monday.
    final currentWeekStart =
        nowMidnight.subtract(Duration(days: nowMidnight.weekday - 1));

    for (var w = 0; w < weeklyKeep; w++) {
      final start = currentWeekStart.subtract(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      RotationFile? earliest;
      for (final f in autos) {
        final ts = f.timestamp.toUtc();
        if (!ts.isBefore(start) && ts.isBefore(end)) {
          if (earliest == null || ts.isBefore(earliest.timestamp.toUtc())) {
            earliest = f;
          }
        }
      }
      if (earliest != null) {
        keepNames.add(earliest.name);
      }
    }

    final toKeep = <RotationFile>[];
    final toDelete = <RotationFile>[];
    for (final f in autos) {
      if (keepNames.contains(f.name)) {
        toKeep.add(f);
      } else {
        toDelete.add(f);
      }
    }
    return BackupRotationDecision(toKeep: toKeep, toDelete: toDelete);
  }
}
