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
    await _exportCatalogFile(
      context: context,
      fetchBytes: (apiService) async =>
          _responseBytes((await apiService.exportData()).data),
      filename:
          'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json',
      extension: 'json',
    );
  }

  /// Export the local catalog as a CSV listing, one row per book.
  ///
  /// Readable inventory, not a backup: unlike [exportCatalogJson] it cannot be
  /// re-imported, and unlike the `.bgbackup` archive it is neither encrypted
  /// nor complete. The rows come from the Rust core with stable English column
  /// names and stable status tokens; both are rewritten here, in the user's
  /// language, because the file is read by a human in a spreadsheet.
  static Future<void> exportCatalogCsv(BuildContext context) async {
    // Resolved before the first await: reading translations needs a mounted
    // context, and the rewrite happens after the fetch.
    final headerLabels = _csvHeaderLabels(context);
    final valueLabels = _csvValueLabels(context);
    await _exportCatalogFile(
      context: context,
      fetchBytes: (apiService) async =>
          _responseBytes((await apiService.exportCsv()).data),
      filename: catalogueCsvFilename(DateTime.now()),
      extension: 'csv',
      transform: (bytes) => localizeCsv(
        bytes,
        headerLabels: headerLabels,
        valueLabels: valueLabels,
      ),
    );
  }

  /// Name of a CSV export, stamped in local time down to the minute.
  ///
  /// The minute matters: a second export on the same day would otherwise
  /// overwrite the first, and overwriting a file a spreadsheet still has open
  /// leaves the user reading the stale import with nothing to signal it. `-`
  /// rather than `:` between hours and minutes, which Windows forbids in a
  /// filename. Kept in step with the `Content-Disposition` the core sends for
  /// the same export (`api/export.rs`).
  @visibleForTesting
  static String catalogueCsvFilename(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'bibliogenius_catalogue_${now.year}-${two(now.month)}-'
        '${two(now.day)}_${two(now.hour)}-${two(now.minute)}.csv';
  }

  /// Fetch an export from the core and hand the resulting file to the user.
  ///
  /// Shared by every catalog export tile: desktop opens a system save dialog,
  /// mobile offers Files-app save or the system share sheet, web triggers a
  /// browser download. [extension] drives the save dialog's file-type filter,
  /// and [transform] optionally post-processes the bytes before they are
  /// written.
  static Future<void> _exportCatalogFile({
    required BuildContext context,
    required Future<List<int>> Function(ApiService) fetchBytes,
    required String filename,
    required String extension,
    List<int> Function(List<int>)? transform,
  }) async {
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
      var bytes = await fetchBytes(apiService);
      if (transform != null) {
        bytes = transform(bytes);
      }

      bool exported = false;

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
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
            allowedExtensions: [extension],
          );
          if (path != null) {
            final file = io.File(path);
            await file.writeAsBytes(bytes);
            exported = true;
          }
        } else {
          if (!context.mounted) {
            // Leaving without dismissing would strand the spinner AND make
            // every later export skip it (`_showLoading` no-ops while one is
            // registered).
            _hideLoading();
            return;
          }
          final choice = await _showMobileExportChoice(context);
          if (choice == _MobileExportChoice.save) {
            final path = await FilePicker.platform.saveFile(
              dialogTitle: saveDialogTitle,
              fileName: filename,
              type: FileType.custom,
              allowedExtensions: [extension],
              bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            );
            exported = path != null;
          } else if (choice == _MobileExportChoice.share) {
            final directory = await getTemporaryDirectory();
            final file = io.File('${directory.path}/$filename');
            await file.writeAsBytes(bytes);
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
        SnackBar(content: Text('$errorMsg : $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Normalize a byte response body. Dio hands back a `Uint8List` for
  /// `ResponseType.bytes`, but a plain `List` is possible depending on the
  /// adapter, and a failed request yields null (which throws here and lands in
  /// the caller's error snackbar).
  static List<int> _responseBytes(dynamic data) =>
      data is List<int> ? data : List<int>.from(data as List);

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

  /// UTF-8 byte-order mark. The CSV exporter emits it so Excel stops reading
  /// the file as Latin-1; it must survive the header rewrite.
  static const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

  /// French spreadsheets split a CSV on `;`, which is what the exporter emits.
  static const String _csvDelimiter = ';';

  /// English column names the core can emit, each one's label living under the
  /// matching `csv_header_<name>` i18n key.
  ///
  /// Not every column is always present: the core drops `price` when the
  /// commerce module is off (`api/export.rs`). So this list says what CAN be
  /// translated, never what the file contains: the rewrite reads the header
  /// row it was handed and works from that.
  @visibleForTesting
  static const List<String> csvColumnNames = [
    'title',
    'authors',
    'isbn',
    'publisher',
    'publication_year',
    'language',
    'ownership_status',
    'reading_status',
    'user_rating',
    'price',
    'tags',
    'added_at',
  ];

  static Map<String, String> _csvHeaderLabels(BuildContext context) => {
    for (final name in csvColumnNames)
      name: TranslationService.translate(context, 'csv_header_$name'),
  };

  /// Translated cell values, keyed by the column they apply to.
  ///
  /// Only the vocabulary the core can write is listed; anything else (a status
  /// replicated from another device, a value a future version adds) is left
  /// untouched by [localizeCsv] rather than blanked. The labels are the ones
  /// the rest of the app already shows for these states, so the spreadsheet
  /// and the screens read the same.
  static Map<String, Map<String, String>> _csvValueLabels(
    BuildContext context,
  ) {
    String label(String key) => TranslationService.translate(context, key);
    return {
      'ownership_status': {
        'owned': label('owned_status'),
        'borrowed': label('reading_status_borrowed'),
        'wishlist': label('csv_ownership_wishlist'),
      },
      'reading_status': {
        'to_read': label('reading_status_to_read'),
        'reading': label('reading_status_reading'),
        'read': label('reading_status_read'),
        'wanting': label('reading_status_wanting'),
        'abandoned': label('reading_status_abandoned'),
      },
    };
  }

  /// Rewrite the export in the user's language: each column header from
  /// [headerLabels] and each status cell from [valueLabels], both keyed by the
  /// English column name the core wrote in the header row.
  ///
  /// The core keeps the column names and the status tokens stable and in
  /// English on purpose (a user who built spreadsheet formulas on an old
  /// export must not see them break, and the HTTP endpoint stays scriptable),
  /// so the localization happens on the way out, where the current UI language
  /// is known.
  ///
  /// Columns are located by name, never by position, because the core does not
  /// always emit the same set: an unknown column keeps its English name and a
  /// missing one is simply not looked for.
  ///
  /// Returns the bytes untouched whenever the payload does not look like the
  /// export it expects: a listing with English names still opens fine, a
  /// mangled one does not.
  ///
  /// Runs on the main isolate. The work is a single linear scan over a file
  /// that is a few hundred KB for a large library, hidden behind the export
  /// spinner; handing it to `compute` would cost two copies of the same bytes
  /// across the isolate boundary for no visible gain.
  @visibleForTesting
  static List<int> localizeCsv(
    List<int> bytes, {
    required Map<String, String> headerLabels,
    required Map<String, Map<String, String>> valueLabels,
  }) {
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == _utf8Bom[0] &&
        bytes[1] == _utf8Bom[1] &&
        bytes[2] == _utf8Bom[2];
    final String body;
    try {
      body = utf8.decode(hasBom ? bytes.sublist(3) : bytes);
    } on FormatException {
      return bytes;
    }

    final rows = _parseCsv(body);
    // A header row is the minimum; anything less is not our export.
    if (rows == null || rows.isEmpty) return bytes;

    final columns = rows.first;
    // Nor is a file whose columns we recognize none of.
    if (!columns.any(headerLabels.containsKey)) return bytes;

    rows[0] = [for (final name in columns) headerLabels[name] ?? name];

    for (final entry in valueLabels.entries) {
      final column = columns.indexOf(entry.key);
      if (column < 0) continue;
      for (var row = 1; row < rows.length; row++) {
        if (column >= rows[row].length) continue;
        final translated = entry.value[rows[row][column]];
        if (translated != null) rows[row][column] = translated;
      }
    }

    final rewritten = utf8.encode(
      _serializeCsv(rows, trailingNewline: body.endsWith('\n')),
    );
    return hasBom ? [..._utf8Bom, ...rewritten] : rewritten;
  }

  /// Parse a `;`-delimited CSV into rows of fields, honouring the quoting the
  /// exporter applies (doubled quotes, delimiters and line breaks inside a
  /// quoted field).
  ///
  /// Returns null on an unterminated quote: the payload is then not the export
  /// we think it is, and rewriting it would corrupt it.
  static List<List<String>>? _parseCsv(String text) {
    final rows = <List<String>>[];
    var fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char != '"') {
          field.write(char);
        } else if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
        continue;
      }
      switch (char) {
        case '"':
          inQuotes = true;
        case _csvDelimiter:
          fields.add(field.toString());
          field.clear();
        case '\n':
          fields.add(field.toString());
          field.clear();
          rows.add(fields);
          fields = <String>[];
        case '\r':
          // A CR outside a quoted field belongs to a CRLF terminator; the LF
          // ends the row on the next turn.
          break;
        default:
          field.write(char);
      }
    }

    if (inQuotes) return null;
    // A file ending on its terminator leaves nothing pending; anything else is
    // a last row without a trailing newline.
    if (field.isNotEmpty || fields.isNotEmpty) {
      fields.add(field.toString());
      rows.add(fields);
    }
    return rows;
  }

  static String _serializeCsv(
    List<List<String>> rows, {
    required bool trailingNewline,
  }) {
    final text = rows
        .map((row) => row.map(_csvEscapeField).join(_csvDelimiter))
        .join('\n');
    return trailingNewline ? '$text\n' : text;
  }

  /// Quote a field the way the exporter does: always, unless it is a plain
  /// number.
  ///
  /// Quoting only what a `;`-delimited reader strictly needs is not enough.
  /// LibreOffice's import dialog remembers its separator checkboxes, so a user
  /// who once opened a comma-separated file sees `Hugo, Victor` split across
  /// two columns; a quoted field is immune to that whatever separators the
  /// reader honours. This must stay in step with `QuoteStyle::NonNumeric` in
  /// `api/export.rs`: rewriting the file re-emits every field, so a laxer rule
  /// here would strip the quoting the core applied.
  ///
  /// Numbers stay bare so the spreadsheet still sorts the year, the rating and
  /// the price as numbers rather than as text.
  ///
  /// Formula defusing is NOT repeated here. The core already prefixes a cell
  /// that would run as a formula (`defuse_formula` in `api/export.rs`), the
  /// values pass through this rewrite untouched, and the only cells replaced
  /// here come from our own `.po` catalogues.
  static String _csvEscapeField(String value) {
    if (value.isNotEmpty && num.tryParse(value) != null) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

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
    // Pre-resolve the failure template for the same reason ({error} is
    // substituted manually in the catch, after the async gaps).
    final failedTemplate = TranslationService.translate(
      context,
      'backup_full_failed',
    );

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
      final isDesktop =
          io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;
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
      debugPrint('[backup-debug] manifest=${summary.manifestJson}');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: Colors.red,
          content: Text(failedTemplate.replaceAll('{error}', '$e')),
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
    // Passphrase is the only offered secret for NEW archives: the directory
    // recovery code is no longer displayed anywhere users could look it up
    // (its settings tile was removed; it survives internally for the hub 401
    // self-heal). Restoring OLD recovery-code archives still works: the
    // restore wizard prompts from the archive's own `unlock_kind`.
    const unlockKind = 'passphrase';
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
                  // Legend: the passphrase is freely chosen here and cannot
                  // be recovered later.
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
                            'backup_unlock_passphrase_hint',
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
                    title: Text(
                      TranslationService.translate(
                        context,
                        'backup_include_identity',
                      ),
                      style: const TextStyle(fontSize: 13),
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
                  final bytes = Uint8List.fromList(
                    utf8.encode(controller.text),
                  );
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
