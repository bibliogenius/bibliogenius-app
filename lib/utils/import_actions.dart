import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/app_snack_bar.dart';

/// CSV / XLSX import flow extracted from `MigrationWizardScreen` so it can be
/// invoked from any screen (settings, wizard, quick actions).
class ImportActions {
  ImportActions._();

  static NavigatorState? _loadingNavigator;

  /// Pick a CSV / XLSX / TXT file and post it to the import endpoint.
  /// Shows a modal loader while uploading and a snackbar with the outcome.
  ///
  /// A file that names no ISBN column is not imported straight away: the
  /// reader sees the columns that were read and chooses to go on without
  /// ISBN or to cancel. The outcome message then says how many books carry
  /// one, because "N books imported" was true and said nothing the day a
  /// 2861-book shelf arrived without a single ISBN.
  static Future<void> importCsv(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final hubDirectory = context.read<HubDirectoryProvider>();
    final importFailedMsg = TranslationService.translate(
      context,
      'migration_import_failed',
    );
    final errorPrefix = TranslationService.translate(
      context,
      'migration_error_prefix',
    );

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      if (!context.mounted) return;

      _showLoading(context);

      final file = result.files.first;
      Future<Response> import({required bool allowMissingIsbn}) => kIsWeb
          ? apiService.importBooks(
              file.bytes!,
              filename: file.name,
              allowMissingIsbn: allowMissingIsbn,
            )
          : apiService.importBooks(
              file.path!,
              allowMissingIsbn: allowMissingIsbn,
            );

      var response = await import(allowMissingIsbn: false);

      _hideLoading();
      if (!context.mounted) return;

      if (response.statusCode == 400 &&
          response.data is Map &&
          response.data['error'] == ApiService.importErrorIsbnColumnMissing) {
        final columns = List<String>.from(response.data['columns'] ?? const []);
        final goOn = await _confirmImportWithoutIsbn(context, columns);
        if (!goOn || !context.mounted) return;

        _showLoading(context);
        response = await import(allowMissingIsbn: true);
        _hideLoading();
        if (!context.mounted) return;
      }

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? importFailedMsg);
      }

      final data = response.data as Map;
      final int imported = data['imported'] ?? 0;
      if (imported > 0) hubDirectory.markCatalogDirty();

      // AppSnackBar draws on the theme's container colours, so the text
      // keeps its contrast in both themes; a raw coloured SnackBar did not.
      final message = _outcomeMessage(context, data);
      if (_outcomeIsWarning(data)) {
        AppSnackBar.error(context, message);
      } else {
        AppSnackBar.success(context, message);
      }
    } catch (e) {
      _hideLoading();
      if (!context.mounted) return;
      AppSnackBar.error(context, '$errorPrefix : $e');
    }
  }

  /// Books arrived but none carries an ISBN: the shelf is usable, everything
  /// keyed on the ISBN is not, and the reader must know before wondering why
  /// no cover ever shows up.
  static bool _outcomeIsWarning(Map data) {
    final int imported = data['imported'] ?? 0;
    final int? withIsbn = data['with_isbn'];
    return imported > 0 && withIsbn == 0;
  }

  static String _outcomeMessage(BuildContext context, Map data) {
    final int imported = data['imported'] ?? 0;
    final int? withIsbn = data['with_isbn'];
    final int rejected = data['rejected_isbn'] ?? 0;

    // The HTTP core path reports a plain count only.
    if (withIsbn == null) {
      return TranslationService.translate(
        context,
        'migration_import_success',
        params: {'count': '$imported'},
      );
    }

    var message = withIsbn == 0 && imported > 0
        ? TranslationService.translate(
            context,
            'migration_import_success_no_isbn',
            params: {'count': '$imported'},
          )
        : TranslationService.translate(
            context,
            'migration_import_success_with_isbn',
            params: {'count': '$imported', 'with_isbn': '$withIsbn'},
          );
    if (rejected > 0) {
      message +=
          ' ${TranslationService.translate(context, 'migration_import_rejected_isbn', params: {'count': '$rejected'})}';
    }
    return message;
  }

  static Future<bool> _confirmImportWithoutIsbn(
    BuildContext context,
    List<String> columns,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(
          TranslationService.translate(ctx, 'import_isbn_column_missing_title'),
        ),
        content: Text(
          TranslationService.translate(
            ctx,
            'import_isbn_column_missing_body',
            params: {'columns': columns.join(', ')},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              TranslationService.translate(ctx, 'import_continue_without_isbn'),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

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
}
