import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/backup_actions.dart';
import 'translation_service.dart';

/// Service that checks for version updates and reminds users to backup their data
class BackupReminderService {
  static const String _lastVersionKey = 'last_app_version';
  static const String _lastReminderKey = 'last_backup_reminder';

  /// Check if we should show a backup reminder
  /// Returns true if a major/minor version change is detected
  static Future<bool> shouldShowReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final lastVersion = prefs.getString(_lastVersionKey);

      // First install - save version and don't show reminder
      if (lastVersion == null) {
        await prefs.setString(_lastVersionKey, currentVersion);
        return false;
      }

      // Check if major or minor version changed
      if (_isSignificantUpdate(lastVersion, currentVersion)) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('BackupReminderService error: $e');
      return false;
    }
  }

  /// Mark current version as acknowledged
  static Future<void> acknowledgeVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      await prefs.setString(_lastVersionKey, packageInfo.version);
      await prefs.setString(_lastReminderKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Failed to acknowledge version: $e');
    }
  }

  /// Check if version change is significant (major or minor bump)
  static bool _isSignificantUpdate(String oldVersion, String newVersion) {
    try {
      final oldParts = oldVersion.split('.');
      final newParts = newVersion.split('.');

      if (oldParts.length < 2 || newParts.length < 2) return false;

      final oldMajor = int.tryParse(oldParts[0]) ?? 0;
      final oldMinor = int.tryParse(oldParts[1]) ?? 0;
      final newMajor = int.tryParse(newParts[0]) ?? 0;
      final newMinor = int.tryParse(newParts[1]) ?? 0;

      // Major version change
      if (newMajor > oldMajor) return true;

      // Minor version change
      if (newMajor == oldMajor && newMinor > oldMinor) return true;

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Show the backup reminder dialog
  static Future<void> showReminderDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.backup, size: 48, color: Colors.orange),
        title: Text(
          TranslationService.translate(context, 'backup_reminder_title'),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TranslationService.translate(context, 'backup_reminder_message'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'backup_reminder_tip',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await acknowledgeVersion();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              TranslationService.translate(context, 'backup_reminder_later'),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              await acknowledgeVersion();
              if (!context.mounted) return;
              Navigator.of(context).pop();
              if (!context.mounted) return;
              await BackupActions.exportCatalogJson(context);
            },
            icon: const Icon(Icons.download),
            label: Text(
              TranslationService.translate(context, 'backup_reminder_export'),
            ),
          ),
        ],
      ),
    );
  }
}
