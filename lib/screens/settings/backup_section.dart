import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';

import '../../widgets/contextual_help_sheet.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../utils/backup_actions.dart';
import '../../widgets/auto_backup_status_card.dart';
import '../../src/rust/api/frb.dart' as rust;
import '../backup_restore_wizard_screen.dart';
import 'settings_scope.dart';

/// Backup and recovery accordion: the encrypted account (backup,
/// recovery after a loss, shared access) leads, followed by the
/// local/offline actions. Merges the former "Backup and export"
/// and "Account" accordions; the visibility keys are the union
/// of both plus the former springboard account tile, so search
/// still surfaces the section for every old query.
class BackupSettingsSection extends StatefulWidget {
  const BackupSettingsSection({super.key});

  @override
  State<BackupSettingsSection> createState() => _BackupSettingsSectionState();
}

class _BackupSettingsSectionState extends State<BackupSettingsSection> {
  SettingsData get _data => settingsDataOf(context);

  @override
  Widget build(BuildContext context) {
    final mfaEnabled = _data.userInfo?['mfa_enabled'] ?? false;
    if (!settingsMatches(context, [
      'backup_section_title',
      'backup_export_catalog_title',
      'backup_export_csv_title',
      'backup_full_title',
      'backup_restore_title',
      'account_sync_title',
      'account_sync_settings_subtitle',
      'account_share_access_title',
      'two_factor_auth',
      'duplicates_title',
      'duplicates_settings_subtitle',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('backup_recovery_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.backup_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'backup_section_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          const AccountSyncTile(),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(
              TranslationService.translate(
                context,
                'account_share_access_title',
              ),
            ),
            subtitle: Text(
              TranslationService.translate(
                context,
                'account_share_access_desc',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            // Same account screen, share-intent framing (title
            // + caption acknowledge the tapped entry).
            onTap: () => context.push('/account-sync?intent=share'),
          ),
          // Honest note on the shared-account trust model: every
          // holder of the passphrase has full access, and durable
          // revocation does not exist yet.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              TranslationService.translate(
                context,
                'account_shared_trust_note',
              ),
              // Themed muted color: grey[600] fails the AA
              // contrast ratio on dark-theme cards.
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!Provider.of<ApiService>(context, listen: false).useFfi)
            ListTile(
              leading: const Icon(Icons.security),
              title: Text(
                TranslationService.translate(context, 'two_factor_auth') ??
                    'Two-Factor Authentication',
              ),
              subtitle: Text(
                mfaEnabled
                    ? (TranslationService.translate(context, 'enabled') ??
                          'Enabled')
                    : (TranslationService.translate(context, 'disabled') ??
                          'Disabled'),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HelpAffordance(topicId: 'two_factor_auth_setting'),
                  const SizedBox(width: 4),
                  Semantics(
                    // The tile's title sits outside the
                    // switch's own node.
                    label: TranslationService.translate(
                      context,
                      'two_factor_auth',
                    ),
                    child: Switch(
                      value: mfaEnabled,
                      onChanged: (val) {
                        if (val) {
                          _setupMfa();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ...offlineDividerWidgets(context),
          ...backupActionTiles(context),
          const DuplicateBooksTile(),
        ],
      ),
    );
  }

  Future<void> _setupMfa() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final response = await apiService.setup2Fa();
      final data = response.data;
      final secret = data['secret'];
      final qrCode = data['qr_code'];

      if (!mounted) return;

      final codeController = TextEditingController();
      String? verifyError;

      await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              TranslationService.translate(context, 'setup_2fa') ?? 'Setup 2FA',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TranslationService.translate(context, 'scan_qr_code') ??
                        'Scan this QR code with your authenticator app:',
                  ),
                  const SizedBox(height: 16),
                  if (qrCode != null)
                    // The secret is offered as selectable text below; the
                    // QR itself has nothing to say to a screen reader.
                    Image.memory(
                      base64Decode(qrCode),
                      height: 200,
                      width: 200,
                      excludeFromSemantics: true,
                    ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '${TranslationService.translate(context, 'secret_key') ?? 'Secret Key'}: $secret',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'verification_code',
                          ) ??
                          'Verification Code',
                      errorText: verifyError,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  TranslationService.translate(context, 'cancel') ?? 'Cancel',
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => verifyError = null);
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'invalid_code',
                          ) ??
                          'Invalid code',
                    );
                    return;
                  }

                  try {
                    await apiService.verify2Fa(secret, code);
                    if (mounted) {
                      Navigator.pop(context);
                      _data.reload();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'mfa_enabled_success',
                                ) ??
                                'MFA Enabled Successfully',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'verification_failed',
                          ) ??
                          'Verification failed',
                    );
                  }
                },
                child: Text(
                  TranslationService.translate(context, 'verify') ?? 'Verify',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_initializing_mfa') ?? 'Error initializing MFA'}: $e',
            ),
          ),
        );
      }
    }
  }
}

/// Tile pointing to the encrypted-account hub (backup + recovery + shared
/// access). Reused by the "Backup and recovery" accordion (default: pushes
/// the hub screen) and the backup capability sheet ([onTap] swaps the sheet
/// content in place instead of stacking a full screen on the popin).
class AccountSyncTile extends StatelessWidget {
  const AccountSyncTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(TranslationService.translate(context, 'account_sync_title')),
      subtitle: Text(
        TranslationService.translate(context, 'account_sync_settings_subtitle'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap ?? () => context.push('/account-sync'),
    );
  }
}

/// Tile pointing to the duplicate-book merge (ADR-070).
///
/// Below the no-account divider, deliberately. Duplicates are what a reader
/// notices after two devices join one account, and the banner on the account
/// screen is the entry point for that case; but the merge itself needs no
/// account, and a library that got its duplicates from a restore rather than
/// a sync would otherwise have no way in at all. Last in the section, after
/// the backup it asks the reader to take first.
class DuplicateBooksTile extends StatelessWidget {
  const DuplicateBooksTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.copy_all_outlined),
      title: Text(TranslationService.translate(context, 'duplicates_title')),
      subtitle: Text(
        TranslationService.translate(context, 'duplicates_settings_subtitle'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/duplicate-books'),
    );
  }
}

/// Section break between the account-based options above and the local,
/// no-account actions below ("Sans compte / hors ligne").
List<Widget> offlineDividerWidgets(BuildContext context) {
  return [
    const Divider(height: 24),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          TranslationService.translate(context, 'backup_offline_divider'),
          // Themed muted color: grey[600] fails the AA contrast ratio on
          // dark-theme cards.
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  ];
}

/// Backup section content (status card + export/restore actions). Shared
/// between the Backup accordion and the springboard "Sauvegarder ma
/// bibliothèque" bottom sheet.
List<Widget> backupActionTiles(BuildContext context) {
  return [
    // Auto-backup status (ADR-037 §6) sits at the top so the green/amber/red
    // state is the first thing the user sees.
    const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AutoBackupStatusCard(),
    ),
    ListTile(
      leading: const Icon(Icons.backup, color: Colors.green),
      title: Text(
        TranslationService.translate(context, 'backup_export_catalog_title'),
      ),
      subtitle: Text(
        TranslationService.translate(context, 'backup_export_catalog_subtitle'),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpAffordance(topicId: 'backup_export_catalog'),
          Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => BackupActions.exportCatalogJson(context),
    ),
    // Readable CSV listing (inventory), next to the JSON export: same
    // delivery flow, different shape. Neither replaces the .bgbackup archive.
    ListTile(
      leading: const Icon(Icons.table_view, color: Colors.green),
      title: Text(
        TranslationService.translate(context, 'backup_export_csv_title'),
      ),
      subtitle: Text(
        TranslationService.translate(context, 'backup_export_csv_subtitle'),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpAffordance(topicId: 'backup_export_csv'),
          Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => BackupActions.exportCatalogCsv(context),
    ),
    // Sauvegarde complète (.bgbackup, ADR-037 §2 writer).
    ListTile(
      leading: const Icon(Icons.shield_outlined, color: Colors.green),
      title: Text(TranslationService.translate(context, 'backup_full_title')),
      subtitle: Text(
        TranslationService.translate(context, 'backup_full_subtitle'),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpAffordance(topicId: 'backup_full'),
          Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => BackupActions.runFullBackup(context),
    ),
    // Restauration .bgbackup (ADR-037 §5 reader).
    ListTile(
      leading: const Icon(Icons.shield, color: Colors.green),
      title: Text(
        TranslationService.translate(context, 'backup_restore_full_title'),
      ),
      subtitle: Text(
        TranslationService.translate(context, 'backup_restore_full_subtitle'),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpAffordance(topicId: 'backup_restore_full'),
          Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BackupRestoreWizardScreen()),
      ),
    ),
    // Restaurer mon catalogue (JSON, legacy).
    ListTile(
      leading: const Icon(Icons.restore, color: Colors.red),
      title: Text(
        TranslationService.translate(context, 'backup_restore_title'),
      ),
      subtitle: Text(
        TranslationService.translate(context, 'backup_restore_subtitle'),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpAffordance(topicId: 'backup_restore_json'),
          Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => BackupActions.restoreCatalogJson(context),
    ),
    // Carte conditionnelle: rollback de la dernière restauration.
    const _RollbackTile(),
  ];
}

/// Conditional "Restaurer la version précédente" tile (ADR-037 §5).
///
/// Polls `list_available_rollbacks_ffi` once at mount and renders nothing
/// when the list is empty. Each rollback is kept on disk for 24h after a
/// Replace restore; the `run_startup_maintenance` purge sweeps expired
/// entries on the next app launch.
class _RollbackTile extends StatefulWidget {
  const _RollbackTile();

  @override
  State<_RollbackTile> createState() => _RollbackTileState();
}

class _RollbackTileState extends State<_RollbackTile> {
  rust.FrbRollbackInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<String> _liveDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/bibliogenius.db';
  }

  Future<void> _refresh() async {
    try {
      final dbPath = await _liveDbPath();
      final list = await rust.listAvailableRollbacksFfi(dbPath: dbPath);
      if (!mounted) return;
      setState(() {
        _info = list.isEmpty ? null : list.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final info = _info;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(ctx, 'backup_rollback_dialog_title'),
        ),
        content: Text(
          TranslationService.translate(ctx, 'backup_rollback_dialog_message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              TranslationService.translate(ctx, 'wizard_restore_button_cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              TranslationService.translate(
                ctx,
                'backup_rollback_dialog_confirm',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dbPath = await _liveDbPath();
      await rust.restoreFromRollbackFfi(
        rollbackPath: info.path,
        dbPath: dbPath,
      );
      // The on-disk DB has been swapped: the global FFI connection is now stale
      // and every write fails with SQLITE_READONLY_DBMOVED until relaunch. Must
      // restart unconditionally; exit needs neither context nor `mounted`, and
      // guarding it would skip the restart if the screen unmounted mid-restore.
      io.exit(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            TranslationService.translate(
              context,
              'backup_rollback_error',
              params: {'error': '$e'},
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final ageHours = (info.ageSeconds / 3600).floor();
    final remainingHours = 24 - ageHours;
    return ListTile(
      leading: const Icon(Icons.history, color: Colors.orange),
      title: Text(
        TranslationService.translate(context, 'backup_rollback_title'),
      ),
      subtitle: Text(
        TranslationService.translate(
          context,
          'backup_rollback_subtitle',
          params: {
            'age_hours': '$ageHours',
            'remaining_hours': '$remainingHours',
          },
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _confirm,
    );
  }
}
