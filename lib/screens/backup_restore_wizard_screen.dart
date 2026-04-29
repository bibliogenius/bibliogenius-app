import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as rust;

/// Whitelist of `SharedPreferences` keys that the local-backup writer (PR #2)
/// captures into `prefs.json` and the restore reader (PR #3) re-applies on
/// success. Kept identical to `BackupActions.runFullBackup` so a round
/// trip through write -> read is lossless. PR #4 will move this list into
/// Rust as the formal whitelist with a drift test.
const List<String> kBackupPrefsWhitelist = <String>[
  'themeStyle',
  'languageCode',
  'country',
];

/// 7-step wizard that drives a full `.bgbackup` restore (ADR-037 §5).
///
/// Steps: file picker -> manifest preview -> secret + HMAC verify -> mode
/// (Replace/Merge) + identity opt-in -> confirmation -> progress -> result
/// (success forces a restart, failure leaves the live DB untouched).
class BackupRestoreWizardScreen extends StatefulWidget {
  const BackupRestoreWizardScreen({super.key});

  @override
  State<BackupRestoreWizardScreen> createState() =>
      _BackupRestoreWizardScreenState();
}

enum _WizardStep { pickFile, preview, secret, mode, confirm, progress, result }

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
  bool _obscureSecret = true;
  String? _secretError;
  bool _verifyingSecret = false;

  String _progressLabel = '';
  String? _failureMessage;
  rust.FrbRestoreSummary? _resultSummary;

  final TextEditingController _secretController = TextEditingController();

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
      setState(() {
        _manifest = m;
        _restoreIdentity = defaultIdentity;
        _step = _WizardStep.preview;
      });
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

      final summary = await rust.restoreBackupFfi(
        archivePath: path,
        secretBytes: secret,
        mode: _mode,
        restoreIdentity: _restoreIdentity,
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
    return Scaffold(
      appBar: AppBar(
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
        const SizedBox(height: 16),
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
        if (_mode == 'replace' && m.identityIncluded) ...[
          const Divider(),
          CheckboxListTile(
            title: Text(_t('wizard_restore_identity_checkbox_title')),
            subtitle: Text(_t('wizard_restore_identity_checkbox_subtitle')),
            value: _restoreIdentity,
            onChanged: (v) => setState(() => _restoreIdentity = v ?? false),
          ),
        ],
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
