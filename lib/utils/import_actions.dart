import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/translation_service.dart';

/// CSV / XLSX import flow extracted from `MigrationWizardScreen` so it can be
/// invoked from any screen (settings, wizard, quick actions).
class ImportActions {
  ImportActions._();

  static NavigatorState? _loadingNavigator;

  /// Pick a CSV / XLSX / TXT file and post it to the import endpoint.
  /// Shows a modal loader while uploading and a snackbar with the outcome.
  static Future<void> importCsv(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
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
      final response = kIsWeb
          ? await apiService.importBooks(file.bytes!, filename: file.name)
          : await apiService.importBooks(file.path!);

      _hideLoading();

      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final imported = response.data['imported'];
        final successMsg = TranslationService.translate(
          context,
          'migration_import_success',
          params: {'count': '$imported'},
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response.data['error'] ?? importFailedMsg);
      }
    } catch (e) {
      _hideLoading();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$errorPrefix : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
