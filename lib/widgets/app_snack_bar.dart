import 'package:flutter/material.dart';
import '../theme/app_design.dart';

/// Centralized SnackBar helper with consistent styling across the app.
///
/// Use semantic methods instead of raw ScaffoldMessenger calls:
///   AppSnackBar.success(context, 'Saved!')
///   AppSnackBar.error(context, 'Something went wrong')
///   AppSnackBar.info(context, 'Tip: you can swipe to delete')
///   AppSnackBar.loading(context, 'Importing...')
class AppSnackBar {
  AppSnackBar._();

  static const _defaultDuration = Duration(seconds: 3);
  static const _errorDuration = Duration(seconds: 5);

  /// Green check - operation completed successfully.
  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool? persist,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      backgroundColorKey: _BgColor.success,
      duration: duration ?? _defaultDuration,
      action: action,
      persist: persist,
    );
  }

  /// Red alert - something failed.
  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool? persist,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      backgroundColorKey: _BgColor.error,
      duration: duration ?? _errorDuration,
      action: action,
      persist: persist,
    );
  }

  /// Neutral info tip.
  static void info(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool? persist,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline,
      backgroundColorKey: _BgColor.info,
      duration: duration ?? _defaultDuration,
      action: action,
      persist: persist,
    );
  }

  /// Indeterminate spinner - call ScaffoldMessenger.hideCurrentSnackBar()
  /// when the operation finishes.
  static void loading(BuildContext context, String message) {
    _show(
      context,
      message: message,
      loadingSpinner: true,
      backgroundColorKey: _BgColor.info,
      duration: const Duration(minutes: 5), // effectively "no auto-dismiss"
    );
  }

  // ---------------------------------------------------------------------------

  static void _show(
    BuildContext context, {
    required String message,
    IconData? icon,
    bool loadingSpinner = false,
    required _BgColor backgroundColorKey,
    required Duration duration,
    SnackBarAction? action,
    bool? persist,
  }) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    switch (backgroundColorKey) {
      case _BgColor.success:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      case _BgColor.error:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
      case _BgColor.info:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
    }

    final leading = loadingSpinner
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Icon(icon, color: fg, size: 20);

    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
      ),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      duration: duration,
      // Flutter defaults `persist` to `action != null` (`snack_bar.dart:303`),
      // which makes `duration` inert: the bar then waits for a tap or a swipe,
      // follows the reader from screen to screen because the ScaffoldMessenger
      // sits above the Navigator, and holds up every message queued behind it.
      // A caller that offers an action AND wants the bar to expire says so.
      persist: persist,
      // Recolour the caller's action against OUR background. Left alone, a
      // SnackBarAction takes its colour from the Material theme, which is
      // `primary`: blue on the blue `primaryContainer` of a success bar, the
      // label barely legible. The message text already computes `fg` for
      // exactly this reason; the action was the one part that did not.
      action: action == null
          ? null
          : SnackBarAction(
              label: action.label,
              onPressed: action.onPressed,
              textColor: fg,
            ),
      content: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}

enum _BgColor { success, error, info }
