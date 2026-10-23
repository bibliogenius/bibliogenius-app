import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/translation_service.dart';
import '../utils/cover_camera_helper.dart';

/// Shows framing tips before the document scanner opens, unless the user
/// ticked "don't show again" earlier or the plain camera is used (auto crop
/// switched off, or no system scanner on this platform).
///
/// Returns false when the user cancelled, so the caller skips the capture.
Future<bool> showCoverScanTipsIfNeeded(BuildContext context) async {
  if (!await CoverCameraHelper.usesDocumentScanner()) return true;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(CoverCameraHelper.scanTipsDismissedPrefKey) ?? false) {
    return true;
  }
  if (!context.mounted) return false;

  // The two system scanners differ: VisionKit opens the crop editor from
  // the thumbnail in the bottom-left corner, ML Kit from its preview screen.
  final bodyKey = Platform.isIOS
      ? 'cover_scan_tips_ios'
      : 'cover_scan_tips_android';
  bool dontShowAgain = false;

  final proceed = await showDialog<bool>(
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
                onPressed: () => Navigator.pop(context, false),
                child: Text(TranslationService.translate(context, 'cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
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
  return proceed ?? false;
}
