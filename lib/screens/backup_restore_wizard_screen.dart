import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/backup_prefs_whitelist.dart';
import '../services/backup_scheduler_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as rust;

/// 7-step wizard that drives a full `.bgbackup` restore (ADR-037 §5).
///
/// Steps: file picker -> manifest preview -> secret + HMAC verify -> mode
/// (Replace/Merge) + identity opt-in -> confirmation -> progress -> result
/// (success forces a restart, failure leaves the live DB untouched).
///
/// Pass [initialArchivePath] to skip the file-picker step and land on the
/// manifest preview directly. Used by the auto-backup bottom sheet when
/// the user taps "Restaurer" on a listed archive: the file lives in
/// Application Support (a hidden folder on macOS) so a generic file
/// picker would force the user to navigate there manually.
class BackupRestoreWizardScreen extends StatefulWidget {
  final String? initialArchivePath;

  const BackupRestoreWizardScreen({super.key, this.initialArchivePath});

  @override
  State<BackupRestoreWizardScreen> createState() =>
      _BackupRestoreWizardScreenState();
}

enum _WizardStep { pickFile, preview, secret, mode, confirm, progress, result }

/// Whether a restore is a same-device restore (the user is restoring a backup
/// produced by THIS device), given the device's peeked `library_uuid` and the
/// archive manifest UUID. Mirrors the backend `same_device` rule
/// (`backup.rs::apply_replace`, ADR-042 §13.3): a `null` or blank local uuid
/// (absent / transiently unreadable store) is NOT a same-device match. The
/// local uuid MUST come from `auth.peekLibraryUuid` (read-only, never minted),
/// otherwise a freshly minted value would falsify this comparison.
@visibleForTesting
bool isSameDeviceRestore(String? localLibraryUuid, String manifestLibraryUuid) {
  final local = localLibraryUuid?.trim() ?? '';
  return local.isNotEmpty && local == manifestLibraryUuid;
}

class _BackupRestoreWizardScreenState extends State<BackupRestoreWizardScreen> {
  _WizardStep _step = _WizardStep.pickFile;

  String? _archivePath;
  rust.FrbBackupManifestPreview? _manifest;
  Uint8List? _secretBytes;
  String _mode = 'replace';
  // Default: aligned with the writer's heuristic. Pre-checked when archive
  // includes identity AND was written with `unlock_kind == "passphrase"`,
  // i.e. the user explicitly opted into clone export.
  bool _restoreIdentity = false;
  /// The device's current `library_uuid`, peeked read-only when the manifest
  /// loads (never minted; see [AuthService.peekLibraryUuid]). `null` when the
  /// device has no identity yet or its store is transiently unreadable. Passed
  /// verbatim to the Rust restore so the same-device detection sees honest
  /// input instead of a freshly minted junk uuid (ADR-042 §13.3).
  String? _localLibraryUuid;
  /// True when [_localLibraryUuid] matches the archive's manifest UUID, i.e.
  /// the user is restoring a backup produced by THIS device. Gates the
  /// identity-choice UX: same-device restores preserve the identity either way,
  /// so they get a reassuring note instead of a reset warning.
  bool _sameDeviceLikely = false;
  bool _obscureSecret = true;
  String? _secretError;
  bool _verifyingSecret = false;
  /// True when we successfully auto-unlocked using the secret already in
  /// secure storage (same-device shortcut). Drives the chip on the mode
  /// step that explains why the secret prompt was skipped, and lets the
  /// restore failure path bounce back to the manual prompt with a clear
  /// hint when the stored secret turns out to no longer match.
  bool _autoUnlocked = false;

  String _progressLabel = '';
  String? _failureMessage;
  rust.FrbRestoreSummary? _resultSummary;

  final TextEditingController _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final preset = widget.initialArchivePath;
    if (preset != null && preset.isNotEmpty) {
      _archivePath = preset;
      // Defer the manifest read until after the first frame so the
      // wizard renders its progress bar / app bar instead of flashing
      // an empty pick-file step.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadManifest();
      });
    }
  }

  @override
  void dispose() {
    // Best-effort: clear the secret bytes we still control before the
    // process holds them on the heap longer than necessary.
    final s = _secretBytes;
    if (s != null) {
      s.fillRange(0, s.length, 0);
    }
    _secretController.clear();
    _secretController.dispose();
    super.dispose();
  }

  String _t(String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  // ---------------------------------------------------------------------------
  // Step transitions
  // ---------------------------------------------------------------------------

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bgbackup'],
      dialogTitle: _t('wizard_restore_picker_dialog_title'),
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    setState(() {
      _archivePath = path;
      _failureMessage = null;
    });
    await _loadManifest();
  }

  Future<void> _loadManifest() async {
    final path = _archivePath;
    if (path == null) return;
    try {
      final m = await rust.readManifestFfi(archivePath: path);
      if (!mounted) return;
      // Schema sanity: surface the "too new" error before asking for a
      // secret. The Rust side enforces this too, but failing fast here
      // avoids the Argon2 cost on an unusable archive.
      if (m.schemaVersion > m.currentSchemaVersion) {
        setState(() {
          _failureMessage = _t(
            'wizard_restore_error_schema_too_new',
            params: {
              'schema': '${m.schemaVersion}',
              'current': '${m.currentSchemaVersion}',
            },
          );
          _step = _WizardStep.result;
          _resultSummary = null;
        });
        return;
      }
      // Default-on the identity checkbox only when the archive carries an
      // identity AND was unlocked via passphrase (the writer's heuristic
      // for "user explicitly opted into clone").
      final defaultIdentity =
          m.identityIncluded && m.unlockKind == 'passphrase';
      // Read-only peek of the device's own `library_uuid`. NEVER mints one
      // (unlike getOrCreateLibraryUuid): a transiently-dark store must surface
      // as "absent", not as a junk uuid that would falsify the same-device
      // detection and trigger a destructive reset (ADR-042 §13.3).
      final auth = context.read<AuthService>();
      final localUuid = await auth.peekLibraryUuid();
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _restoreIdentity = defaultIdentity;
        _localLibraryUuid = localUuid;
        _sameDeviceLikely = isSameDeviceRestore(localUuid, m.libraryUuid);
        _step = _WizardStep.preview;
      });
      // Same-device UX shortcut: if the secret used to encrypt the archive
      // is already on this device's secure storage (typical auto-backup
      // case), skip the manual prompt entirely. The actual HMAC check
      // still runs inside `restore_backup`; if the stored secret no
      // longer matches, we bounce back to the manual prompt with a hint
      // (see _runRestore's BadSignature branch).
      await _maybeAutoUnlock(m);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failureMessage =
            _t('wizard_restore_error_unreadable', params: {'error': '$e'});
        _step = _WizardStep.result;
        _resultSummary = null;
      });
    }
  }

  Future<void> _maybeAutoUnlock(rust.FrbBackupManifestPreview m) async {
    final auth = context.read<AuthService>();
    String? stored;
    if (m.unlockKind == BackupSchedulerService.unlockModeRecoveryCode) {
      stored = await auth.getHubRecoveryCode();
    } else if (m.unlockKind == BackupSchedulerService.unlockModePassphrase) {
      stored = await auth.getAutoBackupPassphrase();
    }
    if (stored == null || stored.isEmpty) return;
    if (!mounted) return;
    final bytes = Uint8List.fromList(utf8.encode(stored));
    _secretBytes?.fillRange(0, _secretBytes!.length, 0);
    _secretBytes = bytes;
    setState(() {
      _autoUnlocked = true;
      _step = _WizardStep.mode;
    });
  }

  Future<void> _verifySecret() async {
    final path = _archivePath;
    if (path == null) return;
    final text = _secretController.text;
    if (text.isEmpty) {
      setState(() => _secretError = _t('wizard_restore_secret_required'));
      return;
    }
    setState(() {
      _verifyingSecret = true;
      _secretError = null;
    });
    final bytes = Uint8List.fromList(utf8.encode(text));
    try {
      // verify_signature is exposed via restore_backup itself: rather than
      // adding another FFI surface, we lean on the wizard flow which calls
      // restore_backup once the user confirms. To avoid running Argon2id
      // twice (verify + restore), we go straight to the mode step here and
      // let the actual restore call surface a secret-error before any disk
      // mutation.
      if (!mounted) return;
      _secretBytes?.fillRange(0, _secretBytes!.length, 0);
      _secretBytes = bytes;
      _secretController.clear();
      setState(() {
        _step = _WizardStep.mode;
        _verifyingSecret = false;
      });
    } catch (e) {
      bytes.fillRange(0, bytes.length, 0);
      if (!mounted) return;
      setState(() {
        _verifyingSecret = false;
        _secretError = _t('wizard_restore_error_bad_secret');
      });
    }
  }

  Future<void> _runRestore() async {
    final path = _archivePath;
    final secret = _secretBytes;
    final manifest = _manifest;
    if (path == null || secret == null || manifest == null) return;

    // Capture the AuthService reference now so we don't need to reach back
    // into the `context` after the heavy async restore call.
    final auth = context.read<AuthService>();

    setState(() {
      _step = _WizardStep.progress;
      _progressLabel = _t('wizard_restore_progress_verifying');
    });

    try {
      final db = await _liveDbPath();
      final coverDir = await _coverDir();

      setState(() => _progressLabel = _mode == 'replace'
          ? _t('wizard_restore_progress_replacing')
          : _t('wizard_restore_progress_merging'));

      // Pass the device's current `library_uuid` (peeked read-only when the
      // manifest loaded) so the Replace path can detect a same-device restore
      // and keep `crypto_keys` intact (ADR-037 §5). It is deliberately the
      // peeked value, NOT getOrCreateLibraryUuid(): minting a fresh uuid here
      // would never match the manifest and would silently flip a same-device
      // restore into a destructive cross-device reset (ADR-042 §13.3). A null
      // value is passed through honestly as "unknown identity".
      final localLibraryUuid = _localLibraryUuid;

      final summary = await rust.restoreBackupFfi(
        archivePath: path,
        secretBytes: secret,
        mode: _mode,
        restoreIdentity: _restoreIdentity,
        localLibraryUuid: localLibraryUuid,
        dbPath: db,
        coverDir: coverDir,
      );

      // Apply identity-related side effects on the Flutter side, per
      // RestoreSummary.libraryUuidAction.
      switch (summary.libraryUuidAction) {
        case 'set':
          final uuid = summary.restoredLibraryUuid;
          if (uuid != null) {
            await auth.setLibraryUuidDualWrite(uuid);
          }
          break;
        case 'clear':
          await auth.clearLibraryUuidBothStores();
          break;
        case 'keep':
        default:
          break;
      }

      // Restore prefs whitelist.
      if (summary.prefsJson.isNotEmpty) {
        await _applyPrefs(summary.prefsJson);
      }

      if (!mounted) return;
      setState(() {
        _resultSummary = summary;
        _step = _WizardStep.result;
        _failureMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Translate the Rust BadSignature surface to a user-facing message;
      // anything else is surfaced verbatim. Live DB stays intact whenever
      // restore_backup returns an error before the rename step.
      final msg = e.toString();
      // Special case: BadSignature after an auto-unlock attempt means the
      // secret stored in secure storage no longer matches this archive
      // (recovery code rotated, mode switched, etc.). Bounce back to the
      // manual prompt with a hint instead of dead-ending on result step.
      if (msg.contains('bad signature') && _autoUnlocked) {
        _secretBytes?.fillRange(0, _secretBytes!.length, 0);
        _secretBytes = null;
        setState(() {
          _autoUnlocked = false;
          _secretError = _t('wizard_restore_secret_auto_unlock_failed');
          _step = _WizardStep.secret;
          _failureMessage = null;
        });
        return;
      }
      String friendly;
      if (msg.contains('bad signature')) {
        friendly = _t('wizard_restore_error_bad_secret');
      } else if (msg.contains('schema_version')) {
        friendly = _t('wizard_restore_error_schema_too_new_short');
      } else if (msg.contains('db_sha256')) {
        friendly = _t('wizard_restore_error_db_hash_mismatch');
      } else {
        friendly = _t('wizard_restore_error_generic', params: {'error': msg});
      }
      setState(() {
        _failureMessage = friendly;
        _step = _WizardStep.result;
        _resultSummary = null;
      });
    } finally {
      // Wipe the secret regardless of outcome.
      _secretBytes?.fillRange(0, _secretBytes!.length, 0);
      _secretBytes = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Filesystem helpers
  // ---------------------------------------------------------------------------

  Future<String> _liveDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/bibliogenius.db';
  }

  Future<String> _coverDir() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/covers';
  }

  Future<void> _applyPrefs(String prefsJson) async {
    try {
      final raw = jsonDecode(prefsJson);
      if (raw is! Map) return;
      final prefs = await SharedPreferences.getInstance();
      for (final key in kBackupPrefsWhitelist) {
        final v = raw[key];
        if (v is String) {
          await prefs.setString(key, v);
        }
      }
    } catch (e) {
      debugPrint('applyPrefs: $e');
    }
  }

  Future<void> _forceRestart() async {
    // Same approach as WhatsApp/Signal post-restore: full process exit. The
    // user relaunches manually. Avoids the in-process global state surgery
    // (OnceLock<DatabaseConnection>, OnceCell<CryptoService>, mDNS
    // refcounts) that would otherwise be required to swap the live DB.
    if (kIsWeb) return;
    io.exit(0);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final progress = _stepProgress(_step);
    // Once a Replace/Merge has succeeded, the on-disk DB has been swapped
    // but the in-memory SeaORM/sqlx pool still points at the old caches.
    // Letting the user navigate away (AppBar back, system back, iOS swipe)
    // produces 500s on the next insert/delete. Block all escape routes
    // until they tap the explicit restart button.
    final mustBlockExit =
        _step == _WizardStep.result && _resultSummary != null;
    return PopScope(
      canPop: !mustBlockExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mustBlockExit) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('wizard_restore_must_restart_hint')),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !mustBlockExit,
          title: Text(_t('wizard_restore_app_bar_title')),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: LinearProgressIndicator(value: progress),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (_step) {
              _WizardStep.pickFile => _buildPickFileStep(),
              _WizardStep.preview => _buildPreviewStep(),
              _WizardStep.secret => _buildSecretStep(),
              _WizardStep.mode => _buildModeStep(),
              _WizardStep.confirm => _buildConfirmStep(),
              _WizardStep.progress => _buildProgressStep(),
              _WizardStep.result => _buildResultStep(),
            },
          ),
        ),
      ),
    );
  }

  double _stepProgress(_WizardStep s) {
    return switch (s) {
      _WizardStep.pickFile => 0.05,
      _WizardStep.preview => 0.2,
      _WizardStep.secret => 0.35,
      _WizardStep.mode => 0.55,
      _WizardStep.confirm => 0.7,
      _WizardStep.progress => 0.9,
      _WizardStep.result => 1.0,
    };
  }

  // -- Step 1: pick file -----------------------------------------------------

  Widget _buildPickFileStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 56),
          const SizedBox(height: 16),
          Text(_t('wizard_restore_step_picker_intro'),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(_t('wizard_restore_button_browse')),
          ),
        ],
      ),
    );
  }

  // -- Step 2: preview -------------------------------------------------------

  Widget _buildPreviewStep() {
    final m = _manifest!;
    final exportDate = _formatRfc3339(m.exportedAt);
    final yes = _t('wizard_restore_yes');
    final no = _t('wizard_restore_no');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('wizard_restore_step_preview_title'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _kvRow(_t('wizard_restore_kv_export_date'), exportDate),
        _kvRow(_t('wizard_restore_kv_library_uuid'), m.libraryUuid),
        _kvRow(
          _t('wizard_restore_kv_schema'),
          _t('wizard_restore_kv_schema_value', params: {
            'schema': '${m.schemaVersion}',
            'current': '${m.currentSchemaVersion}',
          }),
        ),
        _kvRow(_t('wizard_restore_kv_app_version'), m.appVersion),
        _kvRow(_t('wizard_restore_kv_identity_included'),
            m.identityIncluded ? yes : no),
        _kvRow(
          _t('wizard_restore_kv_unlock_kind'),
          m.unlockKind == 'recovery_code'
              ? _t('wizard_restore_unlock_recovery')
              : _t('wizard_restore_unlock_passphrase'),
        ),
        const Divider(height: 32),
        Text(_t('wizard_restore_step_preview_content'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _kvRow(_t('wizard_restore_kv_books'), '${m.booksCount.toInt()}'),
        _kvRow(_t('wizard_restore_kv_copies'), '${m.copiesCount.toInt()}'),
        _kvRow(_t('wizard_restore_kv_loans'), '${m.loansCount.toInt()}'),
        _kvRow(_t('wizard_restore_kv_contacts'), '${m.contactsCount.toInt()}'),
        _kvRow(_t('wizard_restore_kv_tags'), '${m.tagsCount.toInt()}'),
        _kvRow(_t('wizard_restore_kv_local_covers'),
            '${m.coversCount.toInt()}'),
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('wizard_restore_button_cancel')),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => setState(() => _step = _WizardStep.secret),
              child: Text(_t('wizard_restore_button_continue')),
            ),
          ],
        ),
      ],
    );
  }

  // -- Step 3: secret --------------------------------------------------------

  Widget _buildSecretStep() {
    final m = _manifest!;
    final prompt = m.unlockKind == 'recovery_code'
        ? _t('wizard_restore_step_secret_prompt_recovery')
        : _t('wizard_restore_step_secret_prompt_passphrase');
    final label = m.unlockKind == 'recovery_code'
        ? _t('wizard_restore_secret_label_recovery')
        : _t('wizard_restore_secret_label_passphrase');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        TextField(
          controller: _secretController,
          obscureText: _obscureSecret,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            errorText: _secretError,
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureSecret ? Icons.visibility : Icons.visibility_off),
              tooltip: _obscureSecret
                  ? _t('wizard_restore_secret_show')
                  : _t('wizard_restore_secret_hide'),
              onPressed: () =>
                  setState(() => _obscureSecret = !_obscureSecret),
            ),
          ),
          onSubmitted: (_) => _verifySecret(),
        ),
        const SizedBox(height: 16),
        Text(
          _t('wizard_restore_step_secret_hint'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: _verifyingSecret
                  ? null
                  : () => setState(() => _step = _WizardStep.preview),
              child: Text(_t('wizard_restore_button_back')),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _verifyingSecret ? null : _verifySecret,
              child: _verifyingSecret
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_t('wizard_restore_button_continue')),
            ),
          ],
        ),
      ],
    );
  }

  // -- Step 4: mode ----------------------------------------------------------

  Widget _buildModeStep() {
    final m = _manifest!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('wizard_restore_step_mode_title'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_autoUnlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.lock_open, size: 16),
              label: Text(_t(
                m.unlockKind == BackupSchedulerService.unlockModePassphrase
                    ? 'wizard_restore_auto_unlocked_passphrase'
                    : 'wizard_restore_auto_unlocked_recovery_code',
              )),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          title: Text(_t('wizard_restore_mode_replace_title')),
          subtitle: Text(_t('wizard_restore_mode_replace_subtitle')),
          value: 'replace',
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? 'replace'),
        ),
        RadioListTile<String>(
          title: Text(_t('wizard_restore_mode_merge_title')),
          subtitle: Text(_t('wizard_restore_mode_merge_subtitle')),
          value: 'merge',
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? 'merge'),
        ),
        if (_mode == 'replace' && m.identityIncluded) ..._buildIdentityChoice(),
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _WizardStep.secret),
              child: Text(_t('wizard_restore_button_back')),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => setState(() => _step = _WizardStep.confirm),
              child: Text(_t('wizard_restore_button_continue')),
            ),
          ],
        ),
      ],
    );
  }

  /// Identity outcome chooser for Replace, shown only when the archive carries
  /// an identity. Makes the cross-device decision EXPLICIT (ADR-042 §13.2,
  /// §13.3): "migrate" keeps one shared identity (cas 1 clone), "independent
  /// copy" mints a fresh one (cas 3). A same-device restore preserves the
  /// identity either way, so it gets a reassuring note rather than a reset
  /// warning, avoiding a surprise reset for users restoring their own backup.
  List<Widget> _buildIdentityChoice() {
    return [
      const Divider(),
      Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              _t('wizard_restore_identity_section_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: _t('wizard_restore_identity_section_tooltip'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_t('wizard_restore_identity_section_tooltip')),
              ),
            ),
          ),
        ],
      ),
      // Same-device restore: the backend `same_device` guard preserves the
      // identity no matter which option is picked (both collapse to "keep" in
      // backup.rs::apply_replace / frb.rs). Offering a "new identity" choice
      // that cannot fire would be misleading, so we show only the reassuring
      // note. The migrate-vs-copy decision is meaningful only cross-device.
      if (_sameDeviceLikely)
        _identityNote(sameDevice: true)
      else ...[
        RadioListTile<bool>(
          title: Text(_t('wizard_restore_identity_choice_migrate_title')),
          subtitle: Text(_t('wizard_restore_identity_choice_migrate_subtitle')),
          value: true,
          groupValue: _restoreIdentity,
          onChanged: (v) => setState(() => _restoreIdentity = v ?? true),
        ),
        RadioListTile<bool>(
          title: Text(_t('wizard_restore_identity_choice_copy_title')),
          subtitle: Text(_t('wizard_restore_identity_choice_copy_subtitle')),
          value: false,
          groupValue: _restoreIdentity,
          onChanged: (v) => setState(() => _restoreIdentity = v ?? false),
        ),
        const SizedBox(height: 8),
        _identityNote(sameDevice: false),
      ],
    ];
  }

  /// Contextual note under the identity choice: reassuring (secondary) for a
  /// same-device restore, warning (error) for a cross-device one.
  Widget _identityNote({required bool sameDevice}) {
    final cs = Theme.of(context).colorScheme;
    final bg = sameDevice ? cs.secondaryContainer : cs.errorContainer;
    final fg = sameDevice ? cs.onSecondaryContainer : cs.onErrorContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              sameDevice ? Icons.verified_user : Icons.warning_amber,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sameDevice
                    ? _t('wizard_restore_identity_same_device_note')
                    : _t('wizard_restore_identity_cross_device_note'),
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Step 5: confirm -------------------------------------------------------

  Widget _buildConfirmStep() {
    final isReplace = _mode == 'replace';
    final summary = isReplace
        ? _t('wizard_restore_confirm_summary_replace')
        : _t('wizard_restore_confirm_summary_merge');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('wizard_restore_step_confirm_title'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(summary),
          ),
        ),
        if (isReplace) ...[
          const SizedBox(height: 16),
          Text(_t('wizard_restore_confirm_restart_warning')),
        ],
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _WizardStep.mode),
              child: Text(_t('wizard_restore_button_back')),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _runRestore,
              icon: const Icon(Icons.restart_alt),
              label: Text(_t('wizard_restore_button_restore')),
            ),
          ],
        ),
      ],
    );
  }

  // -- Step 6: progress ------------------------------------------------------

  Widget _buildProgressStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          Text(_progressLabel.isEmpty
              ? _t('wizard_restore_progress_default')
              : _progressLabel),
          const SizedBox(height: 12),
          Text(_t('wizard_restore_progress_warning'),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  // -- Step 7: result --------------------------------------------------------

  Widget _buildResultStep() {
    final summary = _resultSummary;
    if (summary != null) {
      final isReplace = summary.mode == 'replace';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Text(_t('wizard_restore_step_result_success_title'),
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          _kvRow(
            _t('wizard_restore_kv_mode'),
            isReplace
                ? _t('wizard_restore_mode_label_replace')
                : _t('wizard_restore_mode_label_merge'),
          ),
          _kvRow(_t('wizard_restore_kv_books'), '${summary.booksAfter.toInt()}'),
          _kvRow(_t('wizard_restore_kv_copies'),
              '${summary.copiesAfter.toInt()}'),
          _kvRow(_t('wizard_restore_kv_contacts'),
              '${summary.contactsAfter.toInt()}'),
          _kvRow(_t('wizard_restore_kv_covers_restored'),
              '${summary.coversRestored.toInt()}'),
          if (summary.identityRestored)
            _kvRow(_t('wizard_restore_kv_identity'),
                _t('wizard_restore_identity_restored_value')),
          if (summary.rollbackPath != null)
            _kvRow(
                _t('wizard_restore_kv_rollback_path'), summary.rollbackPath!),
          const Spacer(),
          if (isReplace)
            FilledButton.icon(
              onPressed: _forceRestart,
              icon: const Icon(Icons.power_settings_new),
              label: Text(_t('wizard_restore_button_close_app')),
            )
          else
            FilledButton.icon(
              onPressed: _forceRestart,
              icon: const Icon(Icons.refresh),
              label: Text(_t('wizard_restore_button_close_to_apply')),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 32),
            const SizedBox(width: 12),
            Text(_t('wizard_restore_step_result_failure_title'),
                style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 16),
        Text(_failureMessage ?? _t('wizard_restore_step_result_failure_unknown')),
        const SizedBox(height: 16),
        Text(_t('wizard_restore_step_result_failure_intact'),
            style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('wizard_restore_button_close')),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => setState(() {
                _step = _WizardStep.pickFile;
                _archivePath = null;
                _manifest = null;
                _failureMessage = null;
                _resultSummary = null;
              }),
              child: Text(_t('wizard_restore_button_retry')),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _formatRfc3339(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
          '${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }
}
