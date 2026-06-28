import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../data/repositories/book_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/flash_message_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/backup_prefs_whitelist.dart';
import '../services/mdns_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as rust;

enum _MobileExportChoice { save, share }

/// Catalog export, JSON restore, and full app reset flows.
///
/// Extracted from `MigrationWizardScreen` so they can be invoked from any
/// screen (currently `SettingsScreen` and the `BackupReminderService` dialog).
class BackupActions {
  BackupActions._();

  /// Computes a non-zero anchor [Rect] for the system share sheet.
  ///
  /// On iPad (and, more strictly, on recent iOS) `share_plus` presents the
  /// share sheet as a popover and requires `sharePositionOrigin` to be set
  /// and non-zero, otherwise it throws
  /// `PlatformException(... sharePositionOrigin ... must be non-zero ...)`.
  /// Backup export and full-backup share calls run from a screen-level
  /// context, so we anchor to that render box when available and fall back
  /// to a 1x1 rect at the screen centre, which is always inside the source
  /// view's coordinate space and satisfies the non-zero requirement.
  static Rect _shareOrigin(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.width > 0 &&
        renderObject.size.height > 0) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    final size = MediaQuery.maybeOf(context)?.size ?? const Size(400, 800);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Public entry points
  // ---------------------------------------------------------------------------

  /// Export the local catalog as a JSON file.
  ///
  /// On desktop: opens a system save dialog. On mobile: lets the user choose
  /// between saving via SAF / Files app or sharing through the system sheet.
  /// On web: triggers a browser download.
  static Future<void> exportCatalogJson(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    // Capture the share-sheet anchor now, while the screen is mounted, so the
    // later share call does not touch `context` across async gaps.
    final shareOrigin = _shareOrigin(context);
    final saveDialogTitle = TranslationService.translate(
      context,
      'save_backup_dialog_title',
    );
    final shareText = TranslationService.translate(
      context,
      'backup_share_text',
    );
    final successMsg = TranslationService.translate(
      context,
      'backup_export_success',
    );
    final errorMsg = TranslationService.translate(
      context,
      'backup_export_error',
    );

    _showLoading(context);
    try {
      final response = await apiService.exportData();
      final filename =
          'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json';

      bool exported = false;

      if (kIsWeb) {
        final blob = html.Blob([response.data]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
        exported = true;
      } else {
        final isDesktop =
            io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;
        if (isDesktop) {
          final path = await FilePicker.platform.saveFile(
            dialogTitle: saveDialogTitle,
            fileName: filename,
            type: FileType.custom,
            allowedExtensions: ['json'],
          );
          if (path != null) {
            final file = io.File(path);
            await file.writeAsBytes(response.data);
            exported = true;
          }
        } else {
          if (!context.mounted) return;
          final choice = await _showMobileExportChoice(context);
          if (choice == _MobileExportChoice.save) {
            final Uint8List bytes = response.data is Uint8List
                ? response.data as Uint8List
                : Uint8List.fromList(List<int>.from(response.data as List));
            final path = await FilePicker.platform.saveFile(
              dialogTitle: saveDialogTitle,
              fileName: filename,
              type: FileType.custom,
              allowedExtensions: ['json'],
              bytes: bytes,
            );
            exported = path != null;
          } else if (choice == _MobileExportChoice.share) {
            final directory = await getTemporaryDirectory();
            final file = io.File('${directory.path}/$filename');
            await file.writeAsBytes(response.data);
            await Share.shareXFiles(
              [XFile(file.path)],
              text: shareText,
              sharePositionOrigin: shareOrigin,
            );
            exported = true;
          }
        }
      }

      _hideLoading();
      if (exported) {
        messenger.showSnackBar(
          SnackBar(content: Text(successMsg), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$errorMsg : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Restore a catalog JSON file. Shows a destructive-action warning before
  /// running, then overwrites the local catalog.
  static Future<void> restoreCatalogJson(BuildContext context) async {
    final confirmed = await _showRestoreWarning(context);
    if (confirmed != true || !context.mounted) return;
    await _handleRestore(context);
  }

  /// Show the three-option reset dialog (delete books / delete books + shelves
  /// + collections / full reset). Each option re-confirms before running.
  static Future<void> showResetDialog(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final collectionsEnabled = themeProvider.collectionsEnabled;

    return showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Réinitialiser l\'application')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choisissez le type de réinitialisation :',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildResetOption(
                  dialogContext,
                  icon: Icons.menu_book,
                  color: Colors.orange,
                  title: 'Supprimer les livres uniquement',
                  description:
                      'Conserve les étagères, paramètres${collectionsEnabled ? ' et collections' : ''}.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetBooks(context);
                  },
                ),
                const SizedBox(height: 12),
                _buildResetOption(
                  dialogContext,
                  icon: Icons.layers_clear,
                  color: Colors.deepOrange,
                  title:
                      'Supprimer livres, étagères${collectionsEnabled ? ' et collections' : ''}',
                  description: 'Conserve uniquement les paramètres.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetBooksShelvesCollections(context);
                  },
                ),
                const SizedBox(height: 12),
                _buildResetOption(
                  dialogContext,
                  icon: Icons.delete_forever,
                  color: Colors.red.shade700,
                  title: 'Réinitialisation complète',
                  description:
                      'Efface TOUTES les données. Retour à l\'état initial.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetAll(context);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Loading overlay
  //
  // We capture the NavigatorState at show-time so the dismissal does not need
  // a fresh BuildContext (which may be unmounted after the awaited work).
  // ---------------------------------------------------------------------------

  static NavigatorState? _loadingNavigator;

  static void _showLoading(BuildContext context) {
    if (_loadingNavigator != null || !context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    _loadingNavigator = navigator;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  static void _hideLoading() {
    final navigator = _loadingNavigator;
    if (navigator == null) return;
    _loadingNavigator = null;
    if (navigator.mounted) {
      navigator.pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Export helpers
  // ---------------------------------------------------------------------------

  static Future<_MobileExportChoice?> _showMobileExportChoice(
    BuildContext context,
  ) {
    return showDialog<_MobileExportChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(
              dialogContext,
              'backup_export_choice_title',
            ),
          ),
          content: Text(
            TranslationService.translate(
              dialogContext,
              'backup_export_choice_message',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                TranslationService.translate(dialogContext, 'cancel'),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _MobileExportChoice.share),
              icon: const Icon(Icons.share),
              label: Text(
                TranslationService.translate(
                  dialogContext,
                  'backup_export_share',
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _MobileExportChoice.save),
              icon: const Icon(Icons.save_alt),
              label: Text(
                TranslationService.translate(
                  dialogContext,
                  'backup_export_save_to_device',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Restore helpers
  // ---------------------------------------------------------------------------

  static Future<bool?> _showRestoreWarning(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⚠️ Attention : Restauration'),
        content: const Text(
          'La restauration d\'une sauvegarde va ÉCRASER toutes vos données actuelles. Cette action est irréversible. Voulez-vous continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirmer l\'écrasement'),
          ),
        ],
      ),
    );
  }

  static Future<void> _handleRestore(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      if (!context.mounted) return;
      _showLoading(context);

      final file = result.files.first;
      List<int> bytes;
      if (kIsWeb) {
        bytes = file.bytes!;
      } else {
        bytes = await io.File(file.path!).readAsBytes();
      }

      final response = await apiService.importBackup(bytes);

      _hideLoading();

      if (response.statusCode == 200) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Bibliothèque restaurée avec succès !'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response.data['error'] ?? 'Échec de la restauration');
      }
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erreur de restauration : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reset helpers
  // ---------------------------------------------------------------------------

  static Widget _buildResetOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmAndResetBooks(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context,
      'Supprimer tous les livres ?',
      'Cette action supprimera tous vos livres mais conservera vos étagères et paramètres. Cette action est irréversible.',
    );
    if (confirmed == true && context.mounted) {
      await _performResetBooks(context);
    }
  }

  static Future<void> _confirmAndResetBooksShelvesCollections(
    BuildContext context,
  ) async {
    final themeProvider = context.read<ThemeProvider>();
    final collectionsEnabled = themeProvider.collectionsEnabled;

    final confirmed = await _showConfirmationDialog(
      context,
      'Supprimer livres, étagères${collectionsEnabled ? ' et collections' : ''} ?',
      'Cette action supprimera tous vos livres, étagères${collectionsEnabled ? ' et collections' : ''} mais conservera vos paramètres. Cette action est irréversible.',
    );
    if (confirmed == true && context.mounted) {
      await _performResetBooksShelvesCollections(context);
    }
  }

  static Future<void> _confirmAndResetAll(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context,
      'Réinitialisation complète ?',
      '⚠️ ATTENTION : Cette action supprimera TOUTES vos données (livres, étagères, collections, paramètres). L\'application reviendra à son état initial. Cette action est IRRÉVERSIBLE.',
      isDestructive: true,
    );
    if (confirmed == true && context.mounted) {
      await _performFullReset(context);
    }
  }

  static Future<bool?> _showConfirmationDialog(
    BuildContext context,
    String title,
    String message, {
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.orange,
            ),
            child: Text(isDestructive ? 'Tout supprimer' : 'Confirmer'),
          ),
        ],
      ),
    );
  }

  static Future<void> _performResetBooks(BuildContext context) async {
    final bookRepo = context.read<BookRepository>();
    final refreshNotifier = context.read<BookRefreshNotifier>();
    final messenger = ScaffoldMessenger.of(context);
    _showLoading(context);
    try {
      final books = await bookRepo.getBooks();
      int deleted = 0;
      for (final book in books) {
        if (book.id != null) {
          await bookRepo.deleteBook(book.id!);
          deleted++;
        }
      }

      _hideLoading();
      refreshNotifier.refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$deleted livres supprimés. Étagères conservées.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<void> _performResetBooksShelvesCollections(
    BuildContext context,
  ) async {
    final bookRepo = context.read<BookRepository>();
    final tagRepo = context.read<TagRepository>();
    final apiService = context.read<ApiService>();
    final themeProvider = context.read<ThemeProvider>();
    final refreshNotifier = context.read<BookRefreshNotifier>();
    final messenger = ScaffoldMessenger.of(context);
    _showLoading(context);
    try {
      final books = await bookRepo.getBooks();
      for (final book in books) {
        if (book.id != null) {
          await bookRepo.deleteBook(book.id!);
        }
      }

      final tags = await tagRepo.getTags();
      for (final tag in tags) {
        // Synthetic (subject-derived) tags have no row to delete.
        if (tag.uuid != null) {
          await tagRepo.deleteTag(tag.uuid!);
        }
      }

      if (themeProvider.collectionsEnabled) {
        final collections = await apiService.getCollections();
        for (final collection in collections) {
          await apiService.deleteCollection(collection.id);
        }
      }

      _hideLoading();
      refreshNotifier.refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Livres, étagères${themeProvider.collectionsEnabled ? ' et collections' : ''} supprimés. Paramètres conservés.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<void> _performFullReset(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final authService = context.read<AuthService>();
    final themeProvider = context.read<ThemeProvider>();
    final flashProvider = context.read<FlashMessageProvider>();
    final notificationProvider = context.read<NotificationProvider>();
    final refreshNotifier = context.read<BookRefreshNotifier>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    _showLoading(context);
    try {
      await apiService.resetApp();
      await authService.clearAll();
      await themeProvider.resetSetup();

      flashProvider.reset();
      notificationProvider.clearAll();

      await MdnsService.stop();
      refreshNotifier.refresh();

      _hideLoading();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Application réinitialisée avec succès.'),
          backgroundColor: Colors.green,
        ),
      );
      router.go('/books');
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Full backup (.bgbackup) — production entry point (ADR-037 §2 writer).
  //
  // Wired to the "Sauvegarde complète" tile (settings_screen.dart). The
  // companion restore wizard lives in `backup_restore_wizard_screen.dart`
  // (ADR-037 §5 reader, this PR).
  // ---------------------------------------------------------------------------

  /// Run the full-backup writer: prompt for secret + identity option, save
  /// to a user-chosen path, write the archive via FFI, show a summary
  /// SnackBar.
  static Future<void> runFullBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final authService = context.read<AuthService>();
    // Capture the share-sheet anchor now, while the screen is mounted, so the
    // later share call does not touch `context` across async gaps.
    final shareOrigin = _shareOrigin(context);

    final input = await _showFullBackupDebugDialog(context);
    if (input == null) return;

    // From here on, `input.secretBytes` is the only place the secret bytes
    // live on the Dart heap. We zero it on every return path.
    try {
      final defaultName =
          'bibliogenius-backup-${_timestampForFilename(DateTime.now())}.bgbackup';

      // Resolve the FFI output path. Desktop platforms expose a real
      // file picker that returns a chosen path; iOS/Android cannot --
      // file_picker's saveFile demands `bytes` upfront on those
      // platforms (the picker is bytes-in, not path-out). We therefore
      // write to a temp path first and surface the file through the
      // system share sheet (Files / iCloud Drive / AirDrop / mail).
      // Mirrors the catalog-export branching at line ~82.
      final isDesktop = io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
      String? outputPath;
      if (isDesktop) {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Exporter la sauvegarde complète',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: ['bgbackup'],
        );
        if (outputPath == null) return;
      } else {
        final tmpDir = await getTemporaryDirectory();
        outputPath = '${tmpDir.path}/$defaultName';
      }

      final libraryUuid = await authService.getOrCreateLibraryUuid();
      final appSupport = await getApplicationSupportDirectory();
      final coverDir = '${appSupport.path}/covers';

      final prefs = await SharedPreferences.getInstance();
      final prefsJson = exportWhitelistedPrefs(prefs.get);

      final summary = await rust.writeBackupFfi(
        outputPath: outputPath,
        secretBytes: input.secretBytes,
        unlockKind: input.unlockKind,
        libraryUuid: libraryUuid,
        includeIdentity: input.includeIdentity,
        prefsJson: prefsJson,
        coverDir: coverDir,
      );

      // Track the timestamp of the last successful manual export so the
      // auto-backup nudge ("export with identity for cross-device
      // migration") can surface only when the user is overdue. Only
      // identity-included exports count toward this signal -- a
      // catalogue-only export does not protect against the "phone lost,
      // peers must re-pair" failure mode the nudge is about.
      if (input.includeIdentity) {
        await prefs.setString(
          'last_full_export_with_identity_at',
          DateTime.now().toIso8601String(),
        );
      }

      final sizeKb = (summary.archiveSizeBytes.toInt() / 1024).round();

      if (!isDesktop) {
        // Hand the freshly-written archive to the OS share sheet so the
        // user can route it to Files, iCloud Drive, AirDrop, mail, etc.
        // No explicit cleanup of the temp copy: iOS purges the temp
        // directory on its own schedule, and a sibling copy made by the
        // destination app would race a delete here.
        await Share.shareXFiles(
          [XFile(outputPath)],
          subject: defaultName,
          text: 'Sauvegarde complète BiblioGenius',
          sharePositionOrigin: shareOrigin,
        );
      }

      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            '.bgbackup OK — '
            '${summary.booksCount.toInt()} livres, '
            '${summary.coversCount.toInt()} covers, '
            '${sizeKb}KB. Identity: ${summary.identityIncluded}.',
          ),
        ),
      );
      debugPrint(
        '[backup-debug] manifest=${summary.manifestJson}',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: Colors.red,
          content: Text('Echec sauvegarde complète: $e'),
        ),
      );
    } finally {
      // Best-effort wipe of the secret buffer. Dart heap is GC-managed,
      // but at least the bytes we control are zeroed before the GC runs.
      input.secretBytes.fillRange(0, input.secretBytes.length, 0);
    }
  }

  static Future<_FullBackupDebugInput?> _showFullBackupDebugDialog(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    String unlockKind = 'passphrase';
    bool includeIdentity = false;
    bool obscure = true;

    final result = await showDialog<_FullBackupDebugInput>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(
              TranslationService.translate(context, 'backup_full_title'),
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'passphrase',
                        label: Text(
                          TranslationService.translate(
                            context,
                            'backup_unlock_passphrase',
                          ),
                        ),
                      ),
                      ButtonSegment(
                        value: 'recovery_code',
                        label: Text(
                          TranslationService.translate(
                            context,
                            'backup_unlock_recovery_code',
                          ),
                        ),
                      ),
                    ],
                    selected: {unlockKind},
                    onSelectionChanged: (s) =>
                        setState(() => unlockKind = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(
                        context,
                        'backup_secret_label',
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Context-sensitive legend: clarifies that a passphrase is
                  // freely chosen here, whereas the recovery code is the one
                  // generated for the profile (Settings > Account).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 15,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                            context,
                            unlockKind == 'passphrase'
                                ? 'backup_unlock_passphrase_hint'
                                : 'backup_unlock_recovery_code_hint',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      "Inclure l'identité",
                      style: TextStyle(fontSize: 13),
                    ),
                    value: includeIdentity,
                    onChanged: (v) =>
                        setState(() => includeIdentity = v ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(TranslationService.translate(context, 'cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isEmpty) return;
                  // Move secret out of the controller as bytes; the String
                  // form remains in the controller's heap until cleared
                  // immediately below.
                  final bytes = Uint8List.fromList(utf8.encode(controller.text));
                  Navigator.of(ctx).pop(
                    _FullBackupDebugInput(
                      secretBytes: bytes,
                      unlockKind: unlockKind,
                      includeIdentity: includeIdentity,
                    ),
                  );
                },
                child: Text(
                  TranslationService.translate(context, 'backup_export_button'),
                ),
              ),
            ],
          ),
        );
      },
    );
    // The controller still references the cleartext String. Dart Strings
    // are immutable so we cannot zero it; clearing the controller at
    // least removes our reference to it.
    controller.clear();
    controller.dispose();
    return result;
  }

  static String _timestampForFilename(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}${two(l.month)}${two(l.day)}-${two(l.hour)}${two(l.minute)}';
  }
}

class _FullBackupDebugInput {
  final Uint8List secretBytes;
  final String unlockKind;
  final bool includeIdentity;

  const _FullBackupDebugInput({
    required this.secretBytes,
    required this.unlockKind,
    required this.includeIdentity,
  });
}
