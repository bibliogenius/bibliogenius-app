import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../widgets/contextual_help_sheet.dart';
import '../../services/translation_service.dart';
import '../../utils/backup_actions.dart';
import '../../widgets/auto_backup_status_card.dart';
import '../../src/rust/api/frb.dart' as rust;
import '../backup_restore_wizard_screen.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Backup and export section: the local copies of the library, then, in a
/// separate zone, what replaces it (restore, roll back). The encrypted
/// account lives in "Account and devices".
class BackupSettingsSection extends StatelessWidget {
  const BackupSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [
      'backup_section_title',
      'backup_export_catalog_title',
      'backup_export_csv_title',
      'backup_full_title',
      'backup_restore_full_title',
      'backup_restore_title',
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      name: 'backup',
      children: [
        ...backupExportTiles(context),
        const SettingsCarefulZoneHeader(),
        ...backupRestoreTiles(context),
        const SizedBox(height: 8),
      ],
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

/// Everything the springboard "Sauvegarder ma bibliothèque" bottom sheet
/// offers: the copies, then the restores.
List<Widget> backupActionTiles(BuildContext context) => [
  ...backupExportTiles(context),
  ...backupRestoreTiles(context),
];

/// Status card + the copies of the library (JSON, CSV, full backup).
List<Widget> backupExportTiles(BuildContext context) {
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
  ];
}

/// What replaces the library: restoring a backup, rolling a restore back.
List<Widget> backupRestoreTiles(BuildContext context) {
  return [
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
