import 'dart:io';

import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AuthService auth;
  late Directory tmp;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = AuthService();
    tmp = await Directory.systemTemp.createTemp('bg-scheduler-test-');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  /// Convenience to seed the bare minimum: enabled flag on, recovery code
  /// in secure storage, scheduler returning a fixed watermark via probe.
  BackupSchedulerService buildService({
    required _FakeBackup fake,
    DateTime? now,
    bool seedRecoveryCode = true,
    bool startEnabled = true,
  }) {
    if (startEnabled) prefs.setBool('auto_backup_enabled', true);
    if (seedRecoveryCode) {
      auth.saveHubRecoveryCode('correct-horse-battery-staple');
    }
    return BackupSchedulerService(
      prefs: prefs,
      authService: auth,
      clock: now != null ? () => now : DateTime.now,
      probeWatermark: fake.probe,
      runBackup: fake.run,
      resolveBackupsDir: () async => tmp,
    );
  }

  group('runIfDue', () {
    test('catch-up at initialize() produces an archive on first boot',
        () async {
      final fake = _FakeBackup(watermarks: ['wm-initial']);
      final svc = buildService(fake: fake);

      await svc.initialize();

      expect(fake.callCount, 1);
      expect(svc.lastBackupTimestamp, isNotNull);
      expect(svc.consecutiveFailures, 0);
      expect(svc.lastOutcome, BackupRunOutcome.ok);
    });

    test(
        'initialize() does NOT re-run when the last archive is younger than '
        'the tick interval (regression: 6:19/6:24/6:36 burst)', () async {
      // Simulate "user toggled auto-backup on at 06:19, edited two books,
      // re-launched the app a few minutes later". Without the overdue
      // gate, every cold start within 24h would produce another archive
      // because the watermark advanced — flooding the history and
      // shrinking the rotation's effective window from days to hours.
      final clockTime = DateTime.utc(2026, 5, 1, 6, 19);
      await prefs.setString(
        'auto_backup_last_ts',
        clockTime.toIso8601String(),
      );
      final fake = _FakeBackup(watermarks: ['wm-edited']);
      final svc = buildService(
        fake: fake,
        // 17 minutes after the last archive — the user's bug report.
        now: clockTime.add(const Duration(minutes: 17)),
      );

      await svc.initialize();

      expect(
        fake.callCount,
        0,
        reason:
            'cold start within tickInterval must not produce a new archive '
            'even when the watermark advanced',
      );
    });

    test('initialize() runs again once tickInterval has elapsed', () async {
      final clockTime = DateTime.utc(2026, 5, 1, 6, 19);
      await prefs.setString(
        'auto_backup_last_ts',
        clockTime.toIso8601String(),
      );
      final fake = _FakeBackup(watermarks: ['wm-after-day']);
      final svc = buildService(
        fake: fake,
        // 25 hours later — overdue.
        now: clockTime.add(const Duration(hours: 25)),
      );

      await svc.initialize();

      expect(fake.callCount, 1);
    });

    test('skips when the watermark has not changed since the last run',
        () async {
      final fake = _FakeBackup(watermarks: ['wm-1', 'wm-1']);
      final svc = buildService(fake: fake);

      final first = await svc.runIfDue();
      final second = await svc.runIfDue();

      expect(first, BackupRunOutcome.ok);
      expect(second, BackupRunOutcome.skippedUnchanged);
      expect(
        fake.callCount,
        1,
        reason: 'two consecutive runs without DB change must produce 1 archive',
      );
    });

    test('runs again when the watermark advances', () async {
      final fake = _FakeBackup(watermarks: ['wm-1', 'wm-2']);
      final svc = buildService(fake: fake);

      await svc.runIfDue();
      await svc.runIfDue();

      expect(fake.callCount, 2);
    });

    test('forceRun bypasses the skip-if-unchanged check', () async {
      final fake = _FakeBackup(watermarks: ['wm-1', 'wm-1']);
      final svc = buildService(fake: fake);

      await svc.runIfDue();
      final outcome = await svc.forceRun();

      expect(outcome, BackupRunOutcome.ok);
      expect(fake.callCount, 2);
    });

    test('does nothing when the toggle is off', () async {
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake, startEnabled: false);

      final outcome = await svc.runIfDue();

      expect(outcome, BackupRunOutcome.disabled);
      expect(fake.callCount, 0);
    });

    test('returns noSecret and bumps failure counter when no recovery code',
        () async {
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake, seedRecoveryCode: false);

      final outcome = await svc.runIfDue();

      expect(outcome, BackupRunOutcome.noSecret);
      expect(svc.consecutiveFailures, 1);
      expect(fake.callCount, 0);
    });

    test('three consecutive runner errors leave the counter at threshold',
        () async {
      final fake = _FakeBackup(
        watermarks: ['wm-1', 'wm-2', 'wm-3'],
        shouldThrow: true,
      );
      final svc = buildService(fake: fake);

      await svc.runIfDue();
      await svc.runIfDue();
      await svc.runIfDue();

      expect(svc.consecutiveFailures, BackupSchedulerService.failureThreshold);
      expect(svc.lastOutcome, BackupRunOutcome.failed);
      expect(svc.lastBackupTimestamp, isNull,
          reason: 'a failed run must not advance the lastBackupTimestamp');
    });

    test('a successful run resets the failure counter to zero', () async {
      prefs.setInt('auto_backup_consecutive_failures', 2);
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake);

      await svc.runIfDue();

      expect(svc.consecutiveFailures, 0);
    });

    test('UTC stamp lands in the auto-prefixed filename', () async {
      final ts = DateTime.utc(2026, 5, 1, 7, 30);
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake, now: ts);

      await svc.runIfDue();

      expect(fake.lastRequest, isNotNull);
      expect(
        p.basename(fake.lastRequest!.outputPath),
        'bibliogenius-auto-20260501-0730.bgbackup',
      );
      expect(
        fake.lastRequest!.outputPath,
        startsWith(tmp.path),
        reason: 'archive must land inside the resolved backups directory',
      );
    });
  });

  group('unlockMode', () {
    test('defaults to recovery_code on a fresh install', () async {
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake);

      expect(svc.unlockMode, BackupSchedulerService.unlockModeRecoveryCode);
    });

    test('passphrase mode reads from auto_backup_passphrase + tags the run',
        () async {
      await auth.saveAutoBackupPassphrase('correct horse battery staple');
      final fake = _FakeBackup(watermarks: ['wm-pp']);
      final svc = buildService(fake: fake);
      await svc.setUnlockMode(BackupSchedulerService.unlockModePassphrase);

      final outcome = await svc.runIfDue();

      expect(outcome, BackupRunOutcome.ok);
      expect(fake.lastRequest, isNotNull);
      expect(
        fake.lastRequest!.unlockKind,
        BackupSchedulerService.unlockModePassphrase,
        reason:
            'unlockKind on the FFI request must reflect the chosen mode '
            'so the manifest stores the correct unlock_kind',
      );
    });

    test('passphrase mode without a passphrase yields noSecret', () async {
      // Auto-backup toggle was meant to gate on the secret being set; this
      // is the defensive belt-and-suspenders path for "user wiped Keychain
      // out-of-band".
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake, seedRecoveryCode: false);
      await svc.setUnlockMode(BackupSchedulerService.unlockModePassphrase);

      final outcome = await svc.runIfDue();

      expect(outcome, BackupRunOutcome.noSecret);
      expect(fake.callCount, 0);
    });

    test('rejects unknown unlock modes', () async {
      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake);

      expect(
        () => svc.setUnlockMode('something-else'),
        throwsArgumentError,
      );
    });
  });

  group('shouldShowCloneExportNudge', () {
    /// Helper: scheduler with the toggle on, last archive at `archiveDaysAgo`,
    /// and a fixed clock so the staleness math is deterministic.
    BackupSchedulerService nudgeScheduler({
      required int archiveDaysAgo,
      DateTime? lastFullExport,
      DateTime? snoozedAt,
    }) {
      final now = DateTime.utc(2026, 5, 1, 12, 0, 0);
      prefs.setBool('auto_backup_enabled', true);
      prefs.setString(
        'auto_backup_last_ts',
        now.subtract(Duration(days: archiveDaysAgo)).toIso8601String(),
      );
      if (lastFullExport != null) {
        prefs.setString(
          'last_full_export_with_identity_at',
          lastFullExport.toIso8601String(),
        );
      }
      if (snoozedAt != null) {
        prefs.setString(
          'auto_backup_clone_nudge_snoozed_at',
          snoozedAt.toIso8601String(),
        );
      }
      return BackupSchedulerService(
        prefs: prefs,
        authService: auth,
        clock: () => now,
        probeWatermark: () async => 'wm',
        runBackup: (_) async => const BackupRunResult(
          archivePath: 'unused',
          archiveSizeBytes: 0,
        ),
        resolveBackupsDir: () async => tmp,
      );
    }

    test('returns false when scheduler is disabled', () {
      prefs.setBool('auto_backup_enabled', false);
      final svc = BackupSchedulerService(
        prefs: prefs,
        authService: auth,
        clock: DateTime.now,
        probeWatermark: () async => 'wm',
        runBackup: (_) async => const BackupRunResult(
          archivePath: 'unused',
          archiveSizeBytes: 0,
        ),
        resolveBackupsDir: () async => tmp,
      );
      expect(svc.shouldShowCloneExportNudge, isFalse);
    });

    test('returns false when first auto-backup is too recent (engagement gate)',
        () {
      final svc = nudgeScheduler(archiveDaysAgo: 3);
      expect(svc.shouldShowCloneExportNudge, isFalse);
    });

    test('returns true when engaged + no clone export ever taken', () {
      final svc = nudgeScheduler(archiveDaysAgo: 14);
      expect(svc.shouldShowCloneExportNudge, isTrue);
    });

    test('returns false when a clone export was taken recently (< 30 days)',
        () {
      final svc = nudgeScheduler(
        archiveDaysAgo: 14,
        lastFullExport: DateTime.utc(2026, 4, 25),
      );
      expect(svc.shouldShowCloneExportNudge, isFalse);
    });

    test('returns true when the last clone export is stale (> 30 days)', () {
      final svc = nudgeScheduler(
        archiveDaysAgo: 60,
        lastFullExport: DateTime.utc(2026, 3, 1),
      );
      expect(svc.shouldShowCloneExportNudge, isTrue);
    });

    test('snooze hides the nudge for the staleness window', () async {
      final svc = nudgeScheduler(
        archiveDaysAgo: 60,
        lastFullExport: DateTime.utc(2026, 3, 1),
        snoozedAt: DateTime.utc(2026, 4, 25),
      );
      expect(
        svc.shouldShowCloneExportNudge,
        isFalse,
        reason: 'snooze < 30 days ago must hide the nudge',
      );
    });

    test('snooze older than the staleness window stops hiding the nudge', () {
      final svc = nudgeScheduler(
        archiveDaysAgo: 60,
        lastFullExport: DateTime.utc(2026, 3, 1),
        snoozedAt: DateTime.utc(2026, 3, 1),
      );
      expect(svc.shouldShowCloneExportNudge, isTrue);
    });
  });

  group('markArchivesCleared', () {
    test(
        'resets lastBackupTimestamp + watermark so the badge returns to never '
        'and the next tick is not skipped (regression: "I deleted all '
        'archives but the badge still says il y a 35min")', () async {
      // Seed the state as if a successful run had just happened.
      await prefs.setString(
        'auto_backup_last_ts',
        DateTime.now().subtract(const Duration(minutes: 35)).toIso8601String(),
      );
      await prefs.setString('auto_backup_last_watermark', 'wm-1');
      await prefs.setInt('auto_backup_consecutive_failures', 2);

      final fake = _FakeBackup(watermarks: ['wm-1']);
      final svc = buildService(fake: fake);

      expect(svc.lastBackupTimestamp, isNotNull,
          reason: 'sanity: state was seeded');

      await svc.markArchivesCleared();

      expect(
        svc.lastBackupTimestamp,
        isNull,
        reason: 'badge should return to "Pas encore de sauvegarde"',
      );
      expect(svc.consecutiveFailures, 0);

      // The next runIfDue must NOT be skipped via watermark match -- the
      // user wants a fresh archive after wiping.
      final outcome = await svc.runIfDue();
      expect(outcome, BackupRunOutcome.ok);
      expect(fake.callCount, 1);
    });
  });

  group('setEnabled', () {
    test('disabling makes future runs skip immediately', () async {
      final fake = _FakeBackup(watermarks: ['wm-1', 'wm-2']);
      final svc = buildService(fake: fake);

      await svc.runIfDue();
      await svc.setEnabled(false);
      final outcome = await svc.runIfDue();

      expect(outcome, BackupRunOutcome.disabled);
      expect(fake.callCount, 1);
    });
  });
}

/// Test double for the FFI watermark probe + writer.
///
/// `watermarks` is consumed in order; once exhausted the last value is
/// reused, mimicking "no further changes". `shouldThrow` flips the
/// runner into a failure mode so we can exercise the failure counter.
class _FakeBackup {
  final List<String> watermarks;
  bool shouldThrow;
  int _watermarkIndex = 0;
  int callCount = 0;
  BackupRunRequest? lastRequest;

  _FakeBackup({required this.watermarks, this.shouldThrow = false});

  Future<String?> probe() async {
    final i = _watermarkIndex.clamp(0, watermarks.length - 1);
    _watermarkIndex++;
    return watermarks[i];
  }

  Future<BackupRunResult> run(BackupRunRequest req) async {
    callCount++;
    lastRequest = req;
    if (shouldThrow) {
      throw StateError('forced runner failure');
    }
    return BackupRunResult(
      archivePath: req.outputPath,
      archiveSizeBytes: 4096,
    );
  }
}
