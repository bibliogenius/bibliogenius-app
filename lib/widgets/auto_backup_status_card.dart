import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../screens/backup_restore_wizard_screen.dart';
import '../services/auth_service.dart';
import '../services/backup_rotation_policy.dart';
import '../services/backup_scheduler_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as rust;
import '../utils/backup_actions.dart';

/// Status badge for the auto-backup scheduler (ADR-037 §6).
///
/// Sits at the top of the Sauvegarde section in Settings. The badge
/// colour reflects the age of the most recent local archive **on this
/// device** (multi-device clarification: the wording explicitly says
/// "sur cet appareil" so a Mac with fresh archives doesn't make an
/// iPhone show false-amber when the iPhone has been closed for a week).
///
/// Tap opens a bottom sheet with the auto-backup toggle, an explicit
/// "Sauvegarder maintenant" trigger, the list of archives currently on
/// disk with per-archive restore actions, the conditional rollback tile
/// (re-uses the FFI `list_available_rollbacks` plumbing), and a
/// confirmation-gated "Vider les sauvegardes auto" action.
class AutoBackupStatusCard extends StatelessWidget {
  const AutoBackupStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BackupSchedulerService>(
      builder: (context, scheduler, _) {
        final state = _AutoBackupBadgeState.from(
          scheduler.lastBackupTimestamp,
          scheduler.isEnabled,
        );
        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: state.bgColor(theme),
          child: InkWell(
            onTap: () => _openSheet(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(state.icon, color: state.fgColor(theme), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.title(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: state.fgColor(theme),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (state.subtitle(context) != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            state.subtitle(context)!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: state.fgColor(theme).withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    color: state.fgColor(theme).withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AutoBackupBottomSheet(),
    );
  }
}

enum _AutoBackupBadge { green, amber, red, never }

class _AutoBackupBadgeState {
  final _AutoBackupBadge level;
  final DateTime? lastTs;
  final bool enabled;

  const _AutoBackupBadgeState(this.level, this.lastTs, this.enabled);

  factory _AutoBackupBadgeState.from(DateTime? ts, bool enabled) {
    if (ts == null) return _AutoBackupBadgeState(_AutoBackupBadge.never, null, enabled);
    final age = DateTime.now().difference(ts);
    if (age > const Duration(days: 30)) {
      return _AutoBackupBadgeState(_AutoBackupBadge.red, ts, enabled);
    }
    if (age > const Duration(days: 7)) {
      return _AutoBackupBadgeState(_AutoBackupBadge.amber, ts, enabled);
    }
    return _AutoBackupBadgeState(_AutoBackupBadge.green, ts, enabled);
  }

  IconData get icon {
    switch (level) {
      case _AutoBackupBadge.green:
        return Icons.check_circle_outline;
      case _AutoBackupBadge.amber:
        return Icons.warning_amber;
      case _AutoBackupBadge.red:
      case _AutoBackupBadge.never:
        return Icons.error_outline;
    }
  }

  Color bgColor(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    switch (level) {
      case _AutoBackupBadge.green:
        return dark
            ? Colors.green.withValues(alpha: 0.20)
            : Colors.green.withValues(alpha: 0.10);
      case _AutoBackupBadge.amber:
        return dark
            ? Colors.orange.withValues(alpha: 0.20)
            : Colors.orange.withValues(alpha: 0.12);
      case _AutoBackupBadge.red:
      case _AutoBackupBadge.never:
        return dark
            ? Colors.red.withValues(alpha: 0.22)
            : Colors.red.withValues(alpha: 0.10);
    }
  }

  Color fgColor(ThemeData theme) {
    switch (level) {
      case _AutoBackupBadge.green:
        return theme.brightness == Brightness.dark
            ? Colors.green.shade200
            : Colors.green.shade900;
      case _AutoBackupBadge.amber:
        return theme.brightness == Brightness.dark
            ? Colors.orange.shade200
            : Colors.orange.shade900;
      case _AutoBackupBadge.red:
      case _AutoBackupBadge.never:
        return theme.brightness == Brightness.dark
            ? Colors.red.shade200
            : Colors.red.shade900;
    }
  }

  String title(BuildContext context) {
    if (lastTs == null) {
      return TranslationService.translate(
        context,
        'auto_backup_status_title_never',
      );
    }
    return TranslationService.translate(
      context,
      'auto_backup_status_title_with_age',
      params: {'age': _formatAge(context, lastTs!)},
    );
  }

  String? subtitle(BuildContext context) {
    if (level == _AutoBackupBadge.amber) {
      return TranslationService.translate(
        context,
        'auto_backup_status_subtitle_amber',
      );
    }
    if (level == _AutoBackupBadge.red) {
      return TranslationService.translate(
        context,
        'auto_backup_status_subtitle_red',
      );
    }
    if (level == _AutoBackupBadge.never) {
      return TranslationService.translate(
        context,
        enabled
            ? 'auto_backup_status_subtitle_never_enabled'
            : 'auto_backup_status_subtitle_disabled',
      );
    }
    return null;
  }
}

String _formatAge(BuildContext context, DateTime ts) {
  final delta = DateTime.now().difference(ts);
  if (delta.inMinutes < 60) {
    return TranslationService.translate(
      context,
      'auto_backup_age_minutes',
      params: {'n': '${delta.inMinutes.clamp(0, 59)}'},
    );
  }
  if (delta.inHours < 24) {
    return TranslationService.translate(
      context,
      'auto_backup_age_hours',
      params: {'n': '${delta.inHours}'},
    );
  }
  return TranslationService.translate(
    context,
    'auto_backup_age_days',
    params: {'n': '${delta.inDays}'},
  );
}

// ============================================================================
// Bottom sheet
// ============================================================================

class _AutoBackupBottomSheet extends StatefulWidget {
  const _AutoBackupBottomSheet();

  @override
  State<_AutoBackupBottomSheet> createState() => _AutoBackupBottomSheetState();
}

class _AutoBackupBottomSheetState extends State<_AutoBackupBottomSheet> {
  List<_ArchiveEntry> _archives = const [];
  rust.FrbRollbackInfo? _rollback;
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final archives = await _scanArchives();
    final rollback = await _findRollback();
    if (!mounted) return;
    setState(() {
      _archives = archives;
      _rollback = rollback;
      _loading = false;
    });
  }

  Future<List<_ArchiveEntry>> _scanArchives() async {
    try {
      final root = Platform.isMacOS || Platform.isIOS
          ? await getApplicationSupportDirectory()
          : await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(root.path, 'backups'));
      if (!await dir.exists()) return const [];
      final files = await dir.list().toList();
      final entries = <_ArchiveEntry>[];
      for (final f in files) {
        if (f is! File) continue;
        final base = p.basename(f.path);
        if (!base.startsWith(BackupRotationPolicy.autoPrefix)) continue;
        final stat = await f.stat();
        entries.add(_ArchiveEntry(
          path: f.path,
          basename: base,
          size: stat.size,
          modified: stat.modified,
        ));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<rust.FrbRollbackInfo?> _findRollback() async {
    try {
      final root = await getApplicationSupportDirectory();
      final dbPath = p.join(root.path, 'bibliogenius.db');
      final list = await rust.listAvailableRollbacksFfi(dbPath: dbPath);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggle(BuildContext context, bool enable) async {
    final scheduler = context.read<BackupSchedulerService>();
    if (!enable) {
      // Disabling never touches secure storage: archives produced under
      // the previous mode stay restorable as long as the user remembers
      // the secret they registered. The wizard reads `unlock_kind` from
      // the manifest so it prompts with the right wording either way.
      await scheduler.setEnabled(false);
      return;
    }
    // Force-show the activation sheet on every off->on transition (Q3 in
    // the design discussion): it explains which secret will be used and
    // lets the user override the default. Without this the recovery
    // code can stay invisible until the day they need to restore.
    final activated = await showAutoBackupActivationSheet(context);
    if (!activated) return;
    if (!context.mounted) return;
    // Trigger an initial run so the user sees an archive show up after
    // toggling on, instead of waiting up to 24h for the next tick.
    unawaited(scheduler.forceRun());
  }

  Future<void> _runCloneExport(BuildContext context) async {
    Navigator.of(context).pop();
    if (!context.mounted) return;
    // Hand off to the existing manual full-backup flow. The user will see
    // the same dialog (passphrase / recovery code, identity opt-in) and
    // can tick "Inclure l'identité" to make the resulting archive
    // suitable for cross-device migration.
    await BackupActions.runFullBackup(context);
  }

  Future<void> _runNow(BuildContext context) async {
    setState(() => _running = true);
    try {
      final outcome =
          await context.read<BackupSchedulerService>().forceRun();
      if (!context.mounted) return;
      if (outcome == BackupRunOutcome.ok) {
        await _refresh();
      } else {
        _showSnack(_runOutcomeMessage(context, outcome));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _restoreArchive(_ArchiveEntry entry) async {
    final navigator = Navigator.of(context);
    // Close the bottom sheet first; otherwise the wizard would push on
    // top of it and the back stack would force the user through the
    // sheet again on cancel.
    navigator.pop();
    // Auto-backups live in Application Support (hidden on macOS), so the
    // wizard's own file picker is unhelpful here. We hand it the path
    // directly via `initialArchivePath` and the wizard skips the
    // pick-file step.
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => BackupRestoreWizardScreen(
          initialArchivePath: entry.path,
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    // Capture the scheduler BEFORE awaiting the dialog so the analyzer
    // does not flag a context.read() across the async gap.
    final scheduler = context.read<BackupSchedulerService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(
          ctx,
          'auto_backup_sheet_clear_confirm_title',
        )),
        content: Text(TranslationService.translate(
          ctx,
          'auto_backup_sheet_clear_confirm_message',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(
              ctx,
              'wizard_restore_button_cancel',
            )),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(TranslationService.translate(
              ctx,
              'auto_backup_sheet_clear_all',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final entry in _archives) {
      try {
        await File(entry.path).delete();
      } catch (_) {
        // Best-effort: a file we cannot delete will reappear after the
        // next refresh; the scheduler's rotation handles repeats.
      }
    }
    // Reset the scheduler bookkeeping so the badge stops pointing at
    // archives the user just deleted, and the next tick produces a
    // fresh archive instead of skipping via the watermark check.
    await scheduler.markArchivesCleared();
    if (mounted) await _refresh();
  }

  Future<void> _restorePreviousVersion() async {
    final info = _rollback;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(
          ctx,
          'backup_rollback_dialog_title',
        )),
        content: Text(TranslationService.translate(
          ctx,
          'backup_rollback_dialog_message',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(
              ctx,
              'wizard_restore_button_cancel',
            )),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(TranslationService.translate(
              ctx,
              'backup_rollback_dialog_confirm',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final root = await getApplicationSupportDirectory();
      final dbPath = p.join(root.path, 'bibliogenius.db');
      await rust.restoreFromRollbackFfi(
        rollbackPath: info.path,
        dbPath: dbPath,
      );
      if (!mounted) return;
      // Force a restart; same approach as the main restore wizard.
      // Avoids the global-state surgery that an in-process swap would
      // otherwise require.
      // ignore: avoid_redundant_argument_values
      await Future<void>.delayed(Duration.zero);
      exit(0);
    } catch (e) {
      if (!mounted) return;
      _showSnack(TranslationService.translate(
        context,
        'backup_rollback_error',
        params: {'error': '$e'},
      ));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _runOutcomeMessage(BuildContext context, BackupRunOutcome outcome) {
    switch (outcome) {
      case BackupRunOutcome.skippedUnchanged:
        return TranslationService.translate(
          context,
          'auto_backup_run_skipped_unchanged',
        );
      case BackupRunOutcome.disabled:
        return TranslationService.translate(
          context,
          'auto_backup_run_disabled',
        );
      case BackupRunOutcome.noSecret:
        return TranslationService.translate(
          context,
          'auto_backup_run_no_secret',
        );
      case BackupRunOutcome.failed:
        return TranslationService.translate(
          context,
          'auto_backup_run_failed',
        );
      case BackupRunOutcome.ok:
        return TranslationService.translate(
          context,
          'auto_backup_run_ok',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = context.watch<BackupSchedulerService>();
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                TranslationService.translate(
                  context,
                  'auto_backup_sheet_title',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(TranslationService.translate(
                  context,
                  'auto_backup_sheet_toggle_label',
                )),
                subtitle: Text(TranslationService.translate(
                  context,
                  'auto_backup_sheet_toggle_subtitle',
                )),
                value: scheduler.isEnabled,
                onChanged: (v) => _toggle(context, v),
              ),
              if (scheduler.shouldShowCloneExportNudge)
                _CloneExportNudgeBanner(
                  onExport: () => _runCloneExport(context),
                  onSnooze: () => scheduler.snoozeCloneExportNudge(),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _running ? null : () => _runNow(context),
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt),
                      label: Text(TranslationService.translate(
                        context,
                        'auto_backup_sheet_run_now',
                      )),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                  context,
                  'auto_backup_sheet_section_archives',
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_archives.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    TranslationService.translate(
                      context,
                      'auto_backup_sheet_no_archives',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                ..._archives.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(_formatTime(e.modified)),
                      subtitle: Text(_formatBytes(e.size)),
                      trailing: TextButton(
                        onPressed: () => _restoreArchive(e),
                        child: Text(TranslationService.translate(
                          context,
                          'auto_backup_sheet_restore_archive',
                        )),
                      ),
                    )),
              if (_rollback != null) ...[
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(TranslationService.translate(
                    context,
                    'backup_rollback_title',
                  )),
                  subtitle: Text(TranslationService.translate(
                    context,
                    'auto_backup_sheet_rollback_subtitle_hours_left',
                    params: {
                      'hours': '${_remainingHours(_rollback!.ageSeconds.toInt())}',
                    },
                  )),
                  trailing: TextButton(
                    onPressed: _restorePreviousVersion,
                    child: Text(TranslationService.translate(
                      context,
                      'backup_rollback_button_undo',
                    )),
                  ),
                ),
              ],
              if (_archives.isNotEmpty) ...[
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _confirmClearAll,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(TranslationService.translate(
                      context,
                      'auto_backup_sheet_clear_all',
                    )),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveEntry {
  final String path;
  final String basename;
  final int size;
  final DateTime modified;

  const _ArchiveEntry({
    required this.path,
    required this.basename,
    required this.size,
    required this.modified,
  });
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatTime(DateTime ts) {
  final l = ts.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// Rollback files are GC'd after 24h (`backup.rs::ROLLBACK_TTL_SECONDS`),
/// so the badge can show "expires in X h" without an extra FFI call.
int _remainingHours(int ageSeconds) {
  const ttlSeconds = 24 * 3600;
  final remaining = ttlSeconds - ageSeconds;
  if (remaining <= 0) return 0;
  return remaining ~/ 3600;
}

void unawaited(Future<void> future) {
  // Tiny shim so we don't pull dart:async at top-level just for this.
  future.catchError((_) {});
}

/// Reminder banner shown inside the auto-backup bottom sheet when the
/// user has been on auto-backup for a while without taking a manual
/// clone-mode export. Auto-backups never carry identity (ADR-037 §6) so
/// a fresh-device restore from auto-backups alone forces every peer
/// through ADR-030 self-heal; a clone-mode export every ~30 days keeps
/// the cross-device migration painless.
class _CloneExportNudgeBanner extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onSnooze;

  const _CloneExportNudgeBanner({
    required this.onExport,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_moon_outlined, color: scheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'auto_backup_clone_nudge_title',
                    ),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              TranslationService.translate(
                context,
                'auto_backup_clone_nudge_body',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onSnooze,
                  child: Text(TranslationService.translate(
                    context,
                    'auto_backup_clone_nudge_snooze',
                  )),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(TranslationService.translate(
                    context,
                    'auto_backup_clone_nudge_export',
                  )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Activation sheet (ADR-037 §6 Option A.2 + Option B coexisting)
// ============================================================================

/// Shown when the user flips the auto-backup toggle from off to on. Forces
/// the user to make an explicit choice about which secret encrypts their
/// archives, and surfaces that secret on screen so they can write it down
/// before relying on it.
///
/// Returns `true` if the user committed to enabling (state is already
/// updated by the sheet itself before returning), `false` on cancel.
Future<bool> showAutoBackupActivationSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _AutoBackupActivationSheet(),
  );
  return result == true;
}

class _AutoBackupActivationSheet extends StatefulWidget {
  const _AutoBackupActivationSheet();

  @override
  State<_AutoBackupActivationSheet> createState() =>
      _AutoBackupActivationSheetState();
}

class _AutoBackupActivationSheetState
    extends State<_AutoBackupActivationSheet> {
  /// Tri-state: `null` while we read the existing recovery code, then
  /// either non-empty (Option A available) or empty (Option B is the
  /// only viable path).
  String? _existingRecoveryCode;
  bool _loaded = false;

  String _mode = BackupSchedulerService.unlockModeRecoveryCode;
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure = true;
  String? _passphraseError;
  bool _submitting = false;

  static const int _minPassphraseLength = 8;

  @override
  void initState() {
    super.initState();
    _loadRecoveryCode();
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadRecoveryCode() async {
    final auth = context.read<AuthService>();
    final code = await auth.getHubRecoveryCode();
    if (!mounted) return;
    setState(() {
      _existingRecoveryCode = code;
      // Default to recovery code when present, otherwise nudge the user
      // straight into the passphrase path -- saves one tap and signals
      // that recovery code is the unavailable option.
      _mode = (code == null || code.isEmpty)
          ? BackupSchedulerService.unlockModePassphrase
          : BackupSchedulerService.unlockModeRecoveryCode;
      _loaded = true;
    });
  }

  String _t(String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  String? _validatePassphrase() {
    final pw = _passphraseController.text;
    final confirm = _confirmController.text;
    if (pw.length < _minPassphraseLength) {
      return _t(
        'auto_backup_activation_passphrase_too_short',
        params: {'min': '$_minPassphraseLength'},
      );
    }
    if (pw != confirm) {
      return _t('auto_backup_activation_passphrase_mismatch');
    }
    return null;
  }

  Future<void> _activate() async {
    setState(() {
      _submitting = true;
      _passphraseError = null;
    });
    try {
      final auth = context.read<AuthService>();
      final scheduler = context.read<BackupSchedulerService>();

      if (_mode == BackupSchedulerService.unlockModePassphrase) {
        final err = _validatePassphrase();
        if (err != null) {
          setState(() => _passphraseError = err);
          return;
        }
        await auth.saveAutoBackupPassphrase(_passphraseController.text);
      }

      await scheduler.setUnlockMode(_mode);
      await scheduler.setEnabled(true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _t('auto_backup_activation_title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _t('auto_backup_activation_explanation'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (!_loaded) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 24),
              ] else ...[
                _buildModeSelector(context),
                const SizedBox(height: 16),
                if (_mode == BackupSchedulerService.unlockModeRecoveryCode &&
                    _existingRecoveryCode != null &&
                    _existingRecoveryCode!.isNotEmpty)
                  _buildRecoveryCodeReveal(context, _existingRecoveryCode!),
                if (_mode == BackupSchedulerService.unlockModeRecoveryCode &&
                    (_existingRecoveryCode == null ||
                        _existingRecoveryCode!.isEmpty))
                  _buildRecoveryCodeMissingHint(context),
                if (_mode == BackupSchedulerService.unlockModePassphrase)
                  _buildPassphraseInputs(context),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(_t('wizard_restore_button_cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _submitting || !_canActivate() ? null : _activate,
                        child: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_t('auto_backup_activation_activate')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _canActivate() {
    if (_mode == BackupSchedulerService.unlockModeRecoveryCode) {
      return _existingRecoveryCode != null && _existingRecoveryCode!.isNotEmpty;
    }
    // Passphrase mode: button stays clickable (validation runs on tap so
    // the user gets actionable feedback inline).
    return true;
  }

  Widget _buildModeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: BackupSchedulerService.unlockModeRecoveryCode,
          // ignore: deprecated_member_use
          groupValue: _mode,
          // ignore: deprecated_member_use
          onChanged: (v) {
            if (v == null) return;
            setState(() => _mode = v);
          },
          title: Text(_t('auto_backup_activation_mode_recovery_code')),
          subtitle: Text(
            _t('auto_backup_activation_mode_recovery_code_hint'),
          ),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: BackupSchedulerService.unlockModePassphrase,
          // ignore: deprecated_member_use
          groupValue: _mode,
          // ignore: deprecated_member_use
          onChanged: (v) {
            if (v == null) return;
            setState(() => _mode = v);
          },
          title: Text(_t('auto_backup_activation_mode_passphrase')),
          subtitle: Text(_t('auto_backup_activation_mode_passphrase_hint')),
        ),
      ],
    );
  }

  Widget _buildRecoveryCodeReveal(BuildContext context, String rawCode) {
    final formatted = HubDirectoryProvider.formatRecoveryCode(rawCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('auto_backup_activation_recovery_code_box_label'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  formatted,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: _t('recovery_code_copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rawCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_t('recovery_code_copied')),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _t('auto_backup_activation_recovery_code_save_advice'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRecoveryCodeMissingHint(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _t('auto_backup_activation_recovery_code_missing'),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }

  Widget _buildPassphraseInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _passphraseController,
          obscureText: _obscure,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _t('auto_backup_activation_passphrase_label'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: _t('auto_backup_activation_passphrase_confirm_label'),
            border: const OutlineInputBorder(),
            errorText: _passphraseError,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'auto_backup_activation_passphrase_save_advice',
            params: {'min': '$_minPassphraseLength'},
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
