import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import '../utils/app_restart.dart';

/// Show the dialog that ends a full reset: the app must be closed before
/// anything else runs, so it cannot be dismissed and its only action closes
/// the app. [onClose] is replaceable for tests.
Future<void> showRestartRequiredDialog(
  BuildContext context, {
  VoidCallback onClose = closeAppForRestart,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RestartRequiredDialog(onClose: onClose),
  );
}

class RestartRequiredDialog extends StatelessWidget {
  const RestartRequiredDialog({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(t('reset_full_done_title')),
        content: Text(t('reset_full_restart_hint')),
        actions: [
          FilledButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.power_settings_new),
            label: Text(t('wizard_restore_button_close_app')),
          ),
        ],
      ),
    );
  }
}
