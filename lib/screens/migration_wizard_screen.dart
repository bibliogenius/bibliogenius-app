import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/repositories/book_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_design.dart';
import '../services/translation_service.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/flash_message_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../services/mdns_service.dart';

class MigrationWizardScreen extends StatefulWidget {
  const MigrationWizardScreen({super.key});

  @override
  State<MigrationWizardScreen> createState() => _MigrationWizardScreenState();
}

class _MigrationWizardScreenState extends State<MigrationWizardScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion & Migration')),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
        ),
        child: SafeArea(
          child: _isProcessing
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                        context,
                        'Importer & Agréger',
                        'Ajoutez des livres provenant d\'autres plateformes à votre bibliothèque actuelle.',
                      ),
                      const SizedBox(height: 12),

                      _buildMigrationCard(
                        context,
                        title: 'Import fichier (CSV / XLSX)',
                        description:
                            'Goodreads, Babelio, Gleeph, ou tout fichier avec colonnes titre/ISBN.',
                        icon: Icons.import_contacts,
                        onTap: () => _handleCsvImport(),
                        color: Colors.orange.shade400,
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader(
                        context,
                        'Sauvegarde & Système',
                        'Gérez les sauvegardes complètes de votre base de données.',
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: 'Exporter une sauvegarde',
                        description:
                            'Créez un fichier JSON contenant toute votre bibliothèque.',
                        icon: Icons.backup,
                        onTap: () => _handleExport(),
                        color: Colors.green.shade400,
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: 'Restaurer une sauvegarde',
                        description:
                            'ATTENTION : Remplace l\'intégralité des données actuelles.',
                        icon: Icons.restore,
                        onTap: () => _showRestoreWarning(),
                        color: Colors.red.shade400,
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader(
                        context,
                        'Organisation',
                        'Gérez la structure de votre bibliothèque.',
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: 'Gérer les étagères',
                        description:
                            'Renommer ou organiser vos étagères virtuelles.',
                        icon: Icons.folder_special,
                        onTap: () => context.push('/shelves-management'),
                        color: Colors.blue.shade400,
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader(
                        context,
                        'Zone de danger',
                        'Réinitialisez tout ou partie de votre bibliothèque.',
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: 'Réinitialiser l\'application',
                        description: 'Effacer les livres ou repartir de zéro.',
                        icon: Icons.delete_forever,
                        onTap: () => _showResetDialog(),
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.blueGrey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCsvImport() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isProcessing = true);

      final file = result.files.first;
      final apiService = Provider.of<ApiService>(context, listen: false);

      final response = kIsWeb
          ? await apiService.importBooks(file.bytes!, filename: file.name)
          : await apiService.importBooks(file.path!);

      if (mounted) {
        setState(() => _isProcessing = false);
        if (response.statusCode == 200) {
          final imported = response.data['imported'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Succès : $imported livres importés !'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(response.data['error'] ?? 'Échec de l\'importation');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleExport() async {
    // Capture context-dependent values up-front to avoid using BuildContext
    // across async gaps (lint: use_build_context_synchronously).
    final apiService = Provider.of<ApiService>(context, listen: false);
    final saveDialogTitle =
        TranslationService.translate(context, 'save_backup_dialog_title');
    final shareText =
        TranslationService.translate(context, 'backup_share_text');
    final successMsg =
        TranslationService.translate(context, 'backup_export_success');
    final errorMsg =
        TranslationService.translate(context, 'backup_export_error');

    try {
      setState(() => _isProcessing = true);
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
        final isDesktop = io.Platform.isMacOS ||
            io.Platform.isWindows ||
            io.Platform.isLinux;
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
          // Mobile (Android / iOS): let the user choose between saving the
          // backup directly to the device (via SAF / Files app) or sharing it
          // through the system share sheet.
          if (!mounted) return;
          final choice = await _showMobileExportChoice();
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
            );
            exported = true;
          }
        }
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        if (exported) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMsg),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMsg : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<_MobileExportChoice?> _showMobileExportChoice() {
    return showDialog<_MobileExportChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(
                dialogContext, 'backup_export_choice_title'),
          ),
          content: Text(
            TranslationService.translate(
                dialogContext, 'backup_export_choice_message'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                  TranslationService.translate(dialogContext, 'cancel')),
            ),
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _MobileExportChoice.share),
              icon: const Icon(Icons.share),
              label: Text(
                TranslationService.translate(
                    dialogContext, 'backup_export_share'),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _MobileExportChoice.save),
              icon: const Icon(Icons.save_alt),
              label: Text(
                TranslationService.translate(
                    dialogContext, 'backup_export_save_to_device'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showRestoreWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Attention : Restauration'),
        content: const Text(
          'La restauration d\'une sauvegarde va ÉCRASER toutes vos données actuelles. Cette action est irréversible. Voulez-vous continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleRestore();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirmer l\'écrasement'),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final collectionsEnabled = themeProvider.collectionsEnabled;

    showDialog(
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

                // Option 1: Delete only books
                _buildResetOption(
                  dialogContext,
                  icon: Icons.menu_book,
                  color: Colors.orange,
                  title: 'Supprimer les livres uniquement',
                  description:
                      'Conserve les étagères, paramètres${collectionsEnabled ? ' et collections' : ''}.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetBooks();
                  },
                ),
                const SizedBox(height: 12),

                // Option 2: Delete books, shelves and collections
                _buildResetOption(
                  dialogContext,
                  icon: Icons.layers_clear,
                  color: Colors.deepOrange,
                  title:
                      'Supprimer livres, étagères${collectionsEnabled ? ' et collections' : ''}',
                  description: 'Conserve uniquement les paramètres.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetBooksShelvesCollections();
                  },
                ),
                const SizedBox(height: 12),

                // Option 3: Full reset
                _buildResetOption(
                  dialogContext,
                  icon: Icons.delete_forever,
                  color: Colors.red.shade700,
                  title: 'Réinitialisation complète',
                  description:
                      'Efface TOUTES les données. Retour à l\'état initial.',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _confirmAndResetAll();
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

  Widget _buildResetOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
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
                  color: color.withOpacity(0.2),
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

  Future<void> _confirmAndResetBooks() async {
    final confirmed = await _showConfirmationDialog(
      'Supprimer tous les livres ?',
      'Cette action supprimera tous vos livres mais conservera vos étagères et paramètres. Cette action est irréversible.',
    );
    if (confirmed == true) {
      await _performResetBooks();
    }
  }

  Future<void> _confirmAndResetBooksShelvesCollections() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final collectionsEnabled = themeProvider.collectionsEnabled;

    final confirmed = await _showConfirmationDialog(
      'Supprimer livres, étagères${collectionsEnabled ? ' et collections' : ''} ?',
      'Cette action supprimera tous vos livres, étagères${collectionsEnabled ? ' et collections' : ''} mais conservera vos paramètres. Cette action est irréversible.',
    );
    if (confirmed == true) {
      await _performResetBooksShelvesCollections();
    }
  }

  Future<void> _confirmAndResetAll() async {
    final confirmed = await _showConfirmationDialog(
      'Réinitialisation complète ?',
      '⚠️ ATTENTION : Cette action supprimera TOUTES vos données (livres, étagères, collections, paramètres). L\'application reviendra à son état initial. Cette action est IRRÉVERSIBLE.',
      isDestructive: true,
    );
    if (confirmed == true) {
      await _performFullReset();
    }
  }

  Future<bool?> _showConfirmationDialog(
    String title,
    String message, {
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.orange,
            ),
            child: Text(isDestructive ? 'Tout supprimer' : 'Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<void> _performResetBooks() async {
    try {
      setState(() => _isProcessing = true);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);

      // Get all books
      final books = await bookRepo.getBooks();

      int deleted = 0;
      for (final book in books) {
        if (book.id != null) {
          await bookRepo.deleteBook(book.id!);
          deleted++;
        }
      }

      if (mounted) {
        context.read<BookRefreshNotifier>().refresh();
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$deleted livres supprimés. Étagères conservées.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _performResetBooksShelvesCollections() async {
    try {
      setState(() => _isProcessing = true);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final tagRepo = Provider.of<TagRepository>(context, listen: false);
      final apiService = Provider.of<ApiService>(context, listen: false);
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

      // Delete all books first
      final books = await bookRepo.getBooks();
      for (final book in books) {
        if (book.id != null) {
          await bookRepo.deleteBook(book.id!);
        }
      }

      // Delete all shelves/tags
      final tags = await tagRepo.getTags();
      for (final tag in tags) {
        await tagRepo.deleteTag(tag.id);
      }

      // Delete all collections if module is enabled
      if (themeProvider.collectionsEnabled) {
        final collections = await apiService.getCollections();
        for (final collection in collections) {
          await apiService.deleteCollection(collection.id);
        }
      }

      if (mounted) {
        context.read<BookRefreshNotifier>().refresh();
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Livres, étagères${themeProvider.collectionsEnabled ? ' et collections' : ''} supprimés. Paramètres conservés.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _performFullReset() async {
    try {
      setState(() => _isProcessing = true);
      final apiService = Provider.of<ApiService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

      await apiService.resetApp();
      await authService.clearAll(); // Clear all auth data
      await themeProvider.resetSetup(); // Reset setup state

      // Clear flash message dismissed state so they reappear after reset
      if (mounted) {
        Provider.of<FlashMessageProvider>(context, listen: false).reset();
      }

      // Clear in-memory notification state (DB rows already wiped by resetApp)
      if (mounted) {
        Provider.of<NotificationProvider>(context, listen: false).clearAll();
      }

      // Stop mDNS so peers no longer see the old library name
      await MdnsService.stop();

      // Trigger UI refresh so book_list_screen reloads (empty) data from DB
      if (mounted) {
        context.read<BookRefreshNotifier>().refresh();
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Application réinitialisée avec succès.'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to library screen after full reset
        context.go('/books');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isProcessing = true);

      final file = result.files.first;
      List<int> bytes;
      if (kIsWeb) {
        bytes = file.bytes!;
      } else {
        bytes = await io.File(file.path!).readAsBytes();
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.importBackup(bytes);

      if (mounted) {
        setState(() => _isProcessing = false);
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bibliothéque restaurée avec succès !'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(response.data['error'] ?? 'Échec de la restauration');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de restauration : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

enum _MobileExportChoice { save, share }
