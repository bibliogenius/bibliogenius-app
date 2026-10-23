import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/cover_camera_helper.dart';

/// Shows framing tips before the document scanner opens, unless the user
/// ticked "don't show again" earlier or the plain camera is used (auto crop
/// switched off, or no system scanner on this platform).
///
/// Returns false when the user cancelled, so the caller skips the capture.
///
/// On Android the scanner comes from Google Play services, which download it
/// on first use. The tips say so and offer the plain camera instead, which
/// switches auto crop off (as the settings toggle does) before anything is
/// downloaded.
Future<bool> showCoverScanTipsIfNeeded(BuildContext context) async {
  if (!await CoverCameraHelper.usesDocumentScanner()) return true;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(CoverCameraHelper.scanTipsDismissedPrefKey) ?? false) {
    return true;
  }
  if (!context.mounted) return false;

  // The two system scanners differ: VisionKit opens the crop editor from
  // the thumbnail in the bottom-left corner, ML Kit from its preview screen.
  final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
  final bodyKey = isIOS ? 'cover_scan_tips_ios' : 'cover_scan_tips_android';
  final themeProvider = context.read<ThemeProvider>();
  bool dontShowAgain = false;

  final choice = await showDialog<_TipsChoice>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            // Large text on a small phone would overflow otherwise.
            scrollable: true,
            title: Text(
              TranslationService.translate(context, 'cover_scan_tips_title'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(TranslationService.translate(context, bodyKey)),
                if (!isIOS) ...[
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.translate(
                      context,
                      'cover_scan_tips_google',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: dontShowAgain,
                  onChanged: (v) =>
                      setDialogState(() => dontShowAgain = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    TranslationService.translate(
                      context,
                      'cover_scan_tips_dont_show_again',
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, _TipsChoice.cancel),
                child: Text(TranslationService.translate(context, 'cancel')),
              ),
              if (!isIOS)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _TipsChoice.plainCamera),
                  child: Text(
                    TranslationService.translate(
                      context,
                      'cover_scan_use_plain_camera',
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, _TipsChoice.scan),
                child: Text(TranslationService.translate(context, 'continue')),
              ),
            ],
          );
        },
      );
    },
  );

  // Honoured even on cancel: the user asked not to see the tips again.
  if (dontShowAgain) {
    await prefs.setBool(CoverCameraHelper.scanTipsDismissedPrefKey, true);
  }
  if (choice == _TipsChoice.plainCamera) {
    await themeProvider.setCoverAutoCropEnabled(false);
  }
  return choice == _TipsChoice.scan || choice == _TipsChoice.plainCamera;
}

enum _TipsChoice { cancel, plainCamera, scan }
