import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Inform the user that data sync activates only after the app is restarted.
///
/// Enrollment persists the account on this device, but the replicated tables are
/// promoted to their conflict-free form (and the sync engine becomes usable) only
/// on the next launch. The backend signals this with `restart_required`; this is
/// the shared prompt every enrollment path shows so the message stays consistent.
Future<void> showAccountSyncRestartDialog(BuildContext context) {
  String t(String key) => TranslationService.translate(context, key);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('account_sync_restart_required_title')),
      content: Text(t('account_sync_restart_required_body')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t('account_sync_restart_required_ok')),
        ),
      ],
    ),
  );
}
