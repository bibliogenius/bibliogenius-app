import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/frb.dart' as rust;
import 'auth_service.dart';
import 'backup_prefs_whitelist.dart';
import 'backup_rotation_policy.dart';

/// Auto-backup scheduler (ADR-037 §6).
///
/// Runs a `.bgbackup` writer every [tickInterval] when enabled, skipping
/// the run when the catalog has not changed since the last archive
/// (compared via the FFI watermark). Persists state in SharedPreferences
/// so it survives restarts. UI state is exposed via [ChangeNotifier]; the
/// settings card subscribes to derive the green/amber/red badge from
/// [lastBackupTimestamp].
///
/// All side effects (FFI watermark probe, FFI archive write, filesystem
/// directory resolution) are passed in as callbacks so unit tests can
/// exercise the scheduler logic without standing up the real backend.
/// Production callers should use [BackupSchedulerService.production].
class BackupSchedulerService extends ChangeNotifier with WidgetsBindingObserver {
  // SharedPreferences keys.
  static const _keyEnabled = 'auto_backup_enabled';
  static const _keyWatermark = 'auto_backup_last_watermark';
  static const _keyLastTs = 'auto_backup_last_ts';
  static const _keyFailureCount = 'auto_backup_consecutive_failures';
  static const _keyUnlockMode = 'auto_backup_unlock_mode';

  /// Set by `BackupActions.runFullBackup` when the user runs a manual
  /// full export with `include_identity == true`. Drives the
  /// "export-with-identity reminder" nudge in the bottom sheet (cross-
  /// device migration safety net; auto-backups never carry identity).
  static const _keyLastFullExportWithIdentity =
      'last_full_export_with_identity_at';

  /// Set when the user dismisses the clone-export nudge with "Plus tard".
  /// The banner stays hidden until either this snooze ages past
  /// [cloneNudgeStaleAfter] or the user actually runs a clone-mode export
  /// (which moves [_keyLastFullExportWithIdentity] forward).
  static const _keyCloneNudgeSnoozedAt = 'auto_backup_clone_nudge_snoozed_at';

  /// Window after which a clone-mode export is considered stale.
  static const Duration cloneNudgeStaleAfter = Duration(days: 30);

  /// Minimum age of the last auto-backup before the nudge is allowed to
  /// surface, avoiding nagging users who just toggled auto-backup on.
  static const Duration cloneNudgeMinEngagement = Duration(days: 7);

  /// Unlock mode values stored in [_keyUnlockMode]. `recoveryCode` reuses
  /// the hub recovery code already in `flutter_secure_storage` (Option A
  /// of ADR-037 §6); `passphrase` uses a user-chosen passphrase stored in
  /// `flutter_secure_storage` under a distinct key (Option B). The
  /// chosen mode is recorded into the manifest's `unlock_kind` so the
  /// restore wizard prompts with the correct wording.
  static const String unlockModeRecoveryCode = 'recovery_code';
  static const String unlockModePassphrase = 'passphrase';

  /// Cadence of the periodic timer. The scheduler also runs once at
  /// [initialize] to catch up missed days when the app was closed.
  static const Duration tickInterval = Duration(hours: 24);

  /// Number of consecutive failed runs after which the UI surfaces an
  /// in-app notification (wired in commit 5).
  static const int failureThreshold = 3;

  final SharedPreferences _prefs;
  final AuthService _auth;
  final DateTime Function() _clock;
  final Future<String?> Function() _probeWatermark;
  final Future<BackupRunResult> Function(BackupRunRequest) _runBackup;
  final Future<Directory> Function() _resolveBackupsDir;

  Timer? _timer;
  bool _initialized = false;
  bool _observerAttached = false;
  BackupRunOutcome? _lastOutcome;

  BackupSchedulerService({
    required SharedPreferences prefs,
    required AuthService authService,
    required DateTime Function() clock,
    required Future<String?> Function() probeWatermark,
    required Future<BackupRunResult> Function(BackupRunRequest) runBackup,
    required Future<Directory> Function() resolveBackupsDir,
  })  : _prefs = prefs,
        _auth = authService,
        _clock = clock,
        _probeWatermark = probeWatermark,
        _runBackup = runBackup,
        _resolveBackupsDir = resolveBackupsDir;

  /// Production wiring: clock = real, watermark probe + writer = real FFI,
  /// backups directory under the platform's Application Support / Documents
  /// folder per ADR-037 §6. Commit 5 plumbs this into the Provider tree.
  factory BackupSchedulerService.production({
    required SharedPreferences prefs,
    required AuthService authService,
  }) {
    return BackupSchedulerService(
      prefs: prefs,
      authService: authService,
      clock: DateTime.now,
      probeWatermark: rust.latestUserDataChangeAtFfi,
      runBackup: _defaultRunBackup,
      resolveBackupsDir: _defaultResolveBackupsDir,
    );
  }

  // -- Public state -----------------------------------------------------

  bool get isEnabled => _prefs.getBool(_keyEnabled) ?? false;

  /// Defaults to [unlockModeRecoveryCode] for backwards compatibility with
  /// the toggle-was-already-on case (commit 5b shipped before the mode
  /// concept; existing installs implicitly used the recovery code).
  String get unlockMode =>
      _prefs.getString(_keyUnlockMode) ?? unlockModeRecoveryCode;

  Future<void> setUnlockMode(String mode) async {
    if (mode != unlockModeRecoveryCode && mode != unlockModePassphrase) {
      throw ArgumentError('Unknown unlock mode: $mode');
    }
    await _prefs.setString(_keyUnlockMode, mode);
    notifyListeners();
  }

  /// `null` when the scheduler has never produced an archive on this
  /// device. The badge UI maps `null` to the "rouge" state.
  DateTime? get lastBackupTimestamp {
    final s = _prefs.getString(_keyLastTs);
    return s == null ? null : DateTime.tryParse(s);
  }

  int get consecutiveFailures => _prefs.getInt(_keyFailureCount) ?? 0;

  BackupRunOutcome? get lastOutcome => _lastOutcome;

  /// True when the user should be reminded to run a manual clone-mode
  /// export (full backup with identity included). Auto-backups never
  /// carry identity by design (ADR-037 §6) so a fresh-device restore
  /// from auto-backups alone forces every peer through ADR-030 self-heal
  /// and resets E2EE pairings; this nudge encourages a periodic clone
  /// export to keep that migration path painless.
  ///
  /// Surfaces only when the user is engaged (auto-backup enabled AND has
  /// run for at least [cloneNudgeMinEngagement]) AND has either never
  /// taken a clone export or did so more than [cloneNudgeStaleAfter]
  /// ago, AND has not snoozed the banner within the same window.
  bool get shouldShowCloneExportNudge {
    if (!isEnabled) return false;
    final lastBackup = lastBackupTimestamp;
    if (lastBackup == null) return false;
    final now = _clock();
    if (now.difference(lastBackup) < cloneNudgeMinEngagement) return false;

    final snoozeStr = _prefs.getString(_keyCloneNudgeSnoozedAt);
    if (snoozeStr != null) {
      final snoozedAt = DateTime.tryParse(snoozeStr);
      if (snoozedAt != null &&
          now.difference(snoozedAt) < cloneNudgeStaleAfter) {
        return false;
      }
    }

    final lastFullStr = _prefs.getString(_keyLastFullExportWithIdentity);
    if (lastFullStr == null) return true;
    final lastFull = DateTime.tryParse(lastFullStr);
    if (lastFull == null) return true;
    return now.difference(lastFull) >= cloneNudgeStaleAfter;
  }

  /// Snooze the nudge for [cloneNudgeStaleAfter]. Called from the
  /// "Plus tard" button on the banner.
  Future<void> snoozeCloneExportNudge() async {
    await _prefs.setString(
      _keyCloneNudgeSnoozedAt,
      _clock().toIso8601String(),
    );
    notifyListeners();
  }

  /// Reset the scheduler's bookkeeping after the user wipes the auto-
  /// backup directory via "Vider les sauvegardes auto". Without this,
  /// the badge would keep reporting "Dernière sauvegarde il y a Xj"
  /// pointing at archives the user just deleted, and the next tick
  /// would skip via the watermark check (storedWatermark == current).
  ///
  /// The fix is symmetric: clear lastBackupTimestamp (so the badge
  /// rolls back to the "never" state matching reality on disk) AND
  /// clear the stored watermark (so the next runIfDue produces a fresh
  /// archive instead of skipping unchanged).
  Future<void> markArchivesCleared() async {
    await _prefs.remove(_keyLastTs);
    await _prefs.remove(_keyWatermark);
    await _prefs.remove(_keyFailureCount);
    notifyListeners();
  }

  // -- Lifecycle --------------------------------------------------------

  /// Wire the periodic timer (when enabled), register the lifecycle
  /// observer (so a foreground resume re-checks the catch-up condition
  /// even if the periodic Timer was paused), and run a catch-up tick
  /// IF the last archive is older than [tickInterval]. Safe to call
  /// multiple times; subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _attachObserver();
    if (isEnabled) {
      _startTimer();
      if (_isOverdue()) {
        await runIfDue();
      }
    }
  }

  /// Resume hook: iOS background suspends the periodic Timer, so the
  /// scheduler would otherwise miss every day the app spent backgrounded
  /// past the 24h mark. Re-checking on resume covers the gap without
  /// adding native background tasks (ADR-037 §6, foreground-only).
  ///
  /// Only fires when the app is genuinely overdue (last archive older
  /// than [tickInterval]). Without this gate, every quick app-switch
  /// after a catalog edit would produce a fresh archive — minutes
  /// apart instead of the documented 24h cadence — and the rotation
  /// would silently shrink the user's history window from "last 7 days"
  /// to "last 7 hours" of edits.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    if (state != AppLifecycleState.resumed) return;
    if (!isEnabled) return;
    if (!_isOverdue()) return;
    runIfDue();
  }

  /// True when no archive exists yet, or the last one is older than
  /// [tickInterval]. The periodic Timer fires at exactly [tickInterval]
  /// so it does not need this gate; only the resume + boot catch-up
  /// paths do, since they can fire at arbitrary intervals.
  bool _isOverdue() {
    final last = lastBackupTimestamp;
    if (last == null) return true;
    return _clock().toUtc().difference(last.toUtc()) >= tickInterval;
  }

  /// Toggle the auto-backup feature. Disabling cancels the periodic timer
  /// immediately; enabling starts it (and only starts it once the service
  /// is initialized, otherwise [initialize] picks it up).
  Future<void> setEnabled(bool enabled) async {
    await _prefs.setBool(_keyEnabled, enabled);
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
    } else if (_initialized && _timer == null) {
      _startTimer();
    }
    notifyListeners();
  }

  /// Bypass the skip-if-unchanged + enabled checks. Used by the debug
  /// "Sauvegarder maintenant" button and tests.
  Future<BackupRunOutcome> forceRun() => runIfDue(force: true);

  /// One scheduler tick: probe the watermark, decide whether to write,
  /// and if so produce an archive + update bookkeeping. Returns the
  /// outcome so callers can branch on it; UI listeners are notified
  /// regardless.
  Future<BackupRunOutcome> runIfDue({bool force = false}) async {
    if (!force && !isEnabled) {
      return _setOutcome(BackupRunOutcome.disabled);
    }

    final String? watermark;
    try {
      watermark = await _probeWatermark();
    } catch (e, st) {
      debugPrint('BackupScheduler watermark probe failed: $e\n$st');
      await _bumpFailureCount();
      return _setOutcome(BackupRunOutcome.failed);
    }
    if (watermark == null) {
      // Production never returns null (library_config seed is always
      // present), but the type allows it. Treat as "skip", do not bump
      // the failure counter.
      return _setOutcome(BackupRunOutcome.skippedUnchanged);
    }

    if (!force) {
      final stored = _prefs.getString(_keyWatermark);
      if (stored == watermark) {
        return _setOutcome(BackupRunOutcome.skippedUnchanged);
      }
    }

    final mode = unlockMode;
    final secret = await _resolveSecret(mode);
    if (secret == null || secret.isEmpty) {
      // Toggle should be gated on the chosen secret being available
      // (`AutoBackupActivationSheet`), so this is the defensive path
      // (e.g. user reset their hub elsewhere and lost the code).
      await _bumpFailureCount();
      return _setOutcome(BackupRunOutcome.noSecret);
    }

    final dir = await _resolveBackupsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ts = _clock().toUtc();
    final filename = 'bibliogenius-auto-${_formatStamp(ts)}.bgbackup';
    final outputPath = p.join(dir.path, filename);

    final libraryUuid = await _auth.getOrCreateLibraryUuid();
    final prefsJson = _exportWhitelistedPrefs();

    Uint8List? secretBytes;
    try {
      secretBytes = Uint8List.fromList(utf8.encode(secret));
      await _runBackup(BackupRunRequest(
        outputPath: outputPath,
        secretBytes: secretBytes,
        libraryUuid: libraryUuid,
        prefsJson: prefsJson,
        unlockKind: mode,
      ));

      await _prefs.setString(_keyWatermark, watermark);
      await _prefs.setString(_keyLastTs, ts.toIso8601String());
      await _prefs.setInt(_keyFailureCount, 0);
      await _applyRotation(dir);
      return _setOutcome(BackupRunOutcome.ok);
    } catch (e, st) {
      debugPrint('BackupScheduler run failed: $e\n$st');
      await _bumpFailureCount();
      return _setOutcome(BackupRunOutcome.failed);
    } finally {
      // Best-effort wipe of the secret buffer. Dart Strings are immutable
      // so the cleartext lives in `secret` until GC, but at least the
      // bytes we control are zeroed.
      if (secretBytes != null) {
        secretBytes.fillRange(0, secretBytes.length, 0);
      }
    }
  }

  /// Returns the currently-active secret string per the chosen
  /// [unlockMode], or `null` if it is missing from secure storage.
  Future<String?> _resolveSecret(String mode) async {
    if (mode == unlockModePassphrase) {
      return await _auth.getAutoBackupPassphrase();
    }
    return await _auth.getHubRecoveryCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
    super.dispose();
  }

  // -- Internals --------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => runIfDue());
  }

  void _attachObserver() {
    if (_observerAttached) return;
    // Guard against pure-dart contexts where the binding has not been
    // initialized (defensive: in production main() always initializes
    // it; in unit tests TestWidgetsFlutterBinding does too).
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (e) {
      debugPrint('BackupScheduler observer attach skipped: $e');
    }
  }

  BackupRunOutcome _setOutcome(BackupRunOutcome outcome) {
    _lastOutcome = outcome;
    notifyListeners();
    return outcome;
  }

  Future<void> _bumpFailureCount() async {
    final cur = _prefs.getInt(_keyFailureCount) ?? 0;
    await _prefs.setInt(_keyFailureCount, cur + 1);
  }

  String _exportWhitelistedPrefs() => exportWhitelistedPrefs(_prefs.get);

  Future<void> _applyRotation(Directory dir) async {
    if (!await dir.exists()) return;
    final entries = await dir.list().toList();
    final candidates = <RotationFile>[];
    for (final e in entries) {
      if (e is! File) continue;
      final base = p.basename(e.path);
      if (!base.startsWith(BackupRotationPolicy.autoPrefix)) continue;
      final ts = _parseStamp(base);
      if (ts == null) continue;
      candidates.add(RotationFile(name: base, timestamp: ts));
    }
    final decision =
        BackupRotationPolicy.decide(candidates, now: _clock().toUtc());
    for (final f in decision.toDelete) {
      try {
        await File(p.join(dir.path, f.name)).delete();
      } catch (e) {
        // A file we cannot delete this round will be retried next tick;
        // not worth crashing the scheduler over.
        debugPrint('BackupScheduler rotation: cannot delete ${f.name}: $e');
      }
    }
  }
}

// ===========================================================================
// Production runner + path resolver. Kept top-level so the production factory
// can wire them without instantiating a class. Tests inject their own.
// ===========================================================================

Future<BackupRunResult> _defaultRunBackup(BackupRunRequest req) async {
  final coverDirRoot = await getApplicationSupportDirectory();
  final coverDir = p.join(coverDirRoot.path, 'covers');

  final summary = await rust.writeBackupFfi(
    outputPath: req.outputPath,
    secretBytes: req.secretBytes,
    // Driven by the user's choice in AutoBackupActivationSheet
    // (recovery code or passphrase). Identity always off for
    // auto-backups (ADR-037 §6).
    unlockKind: req.unlockKind,
    libraryUuid: req.libraryUuid,
    includeIdentity: false,
    prefsJson: req.prefsJson,
    coverDir: coverDir,
  );

  return BackupRunResult(
    archivePath: summary.archivePath,
    archiveSizeBytes: summary.archiveSizeBytes.toInt(),
  );
}

Future<Directory> _defaultResolveBackupsDir() async {
  final root = Platform.isMacOS || Platform.isIOS
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  return Directory(p.join(root.path, 'backups'));
}

// ===========================================================================
// Plain data carriers exposed to deps callbacks (test seam).
// ===========================================================================

class BackupRunRequest {
  final String outputPath;
  final Uint8List secretBytes;
  final String libraryUuid;
  final String prefsJson;

  /// Either `'recovery_code'` or `'passphrase'`. Mirrors
  /// `BackupSchedulerService.unlockMode` -- written into the manifest's
  /// `unlock_kind` so the restore wizard can prompt with the matching
  /// wording.
  final String unlockKind;

  const BackupRunRequest({
    required this.outputPath,
    required this.secretBytes,
    required this.libraryUuid,
    required this.prefsJson,
    required this.unlockKind,
  });
}

class BackupRunResult {
  final String archivePath;
  final int archiveSizeBytes;

  const BackupRunResult({
    required this.archivePath,
    required this.archiveSizeBytes,
  });
}

enum BackupRunOutcome {
  /// Archive was written successfully.
  ok,

  /// Watermark unchanged since last successful run.
  skippedUnchanged,

  /// Toggle is off; the periodic timer should not be running.
  disabled,

  /// Recovery code missing from secure storage. Failure counter bumped.
  noSecret,

  /// Watermark probe or writer threw. Failure counter bumped.
  failed,
}

// ---------------------------------------------------------------------------
// Filename helpers shared with the test suite.
// ---------------------------------------------------------------------------

String _formatStamp(DateTime ts) {
  final u = ts.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}-${two(u.hour)}${two(u.minute)}';
}

final RegExp _stampRegex = RegExp(
  r'^bibliogenius-auto-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\.bgbackup$',
);

DateTime? _parseStamp(String basename) {
  final m = _stampRegex.firstMatch(basename);
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  );
}
