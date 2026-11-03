import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/translation_service.dart';
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

  /// Red alert - something failed. With [queue], it waits for the message
  /// on screen to close instead of replacing it.
  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool? persist,
    bool queue = false,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      backgroundColorKey: _BgColor.error,
      duration: duration ?? _errorDuration,
      action: action,
      persist: persist,
      replace: !queue,
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

  /// How long an Undo stays up for a sighted reader.
  static const undoDuration = Duration(seconds: 5);

  /// Says what was just done and offers to take it back: the one message
  /// for an action that runs at once instead of asking first.
  ///
  /// Five seconds, unless a screen reader is on: the message then stays
  /// until it is used or dismissed. Flutter no longer holds a timed bar for
  /// VoiceOver or TalkBack (only `persist` stops the timer), and five
  /// seconds is not enough to hear the message and find its button.
  static UndoableMessage undoable(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
  }) {
    final undoable = UndoableMessage._(ScaffoldMessenger.of(context));
    final controller = _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      backgroundColorKey: _BgColor.success,
      duration: undoDuration,
      action: SnackBarAction(
        label: TranslationService.translate(context, 'action_undo'),
        onPressed: onUndo,
      ),
      persist: MediaQuery.accessibleNavigationOf(context),
      onShown: undoable._markShown,
    );
    return undoable.._attach(controller);
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

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(
    BuildContext context, {
    required String message,
    IconData? icon,
    bool loadingSpinner = false,
    required _BgColor backgroundColorKey,
    required Duration duration,
    SnackBarAction? action,
    bool? persist,
    VoidCallback? onShown,
    bool replace = true,
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

    final content = Semantics(
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
    );

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
      content: onShown == null
          ? content
          : _OnShown(onShown: onShown, child: content),
    );

    final messenger = ScaffoldMessenger.of(context);
    if (replace) messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(snackBar);
  }
}

enum _BgColor { success, error, info }

/// A message shown by [AppSnackBar.undoable].
class UndoableMessage {
  UndoableMessage._(this._messenger);

  final ScaffoldMessengerState _messenger;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  _controller;
  bool _isOpen = true;

  /// Built on screen at least once. A new bar waits in the messenger's
  /// queue while the one before it leaves, and only the bar on screen can
  /// be closed.
  bool _isShown = false;
  bool _closeOnceShown = false;

  void _attach(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    _controller = controller;
    controller.closed.then((_) => _isOpen = false);
  }

  /// Called while the bar builds: a dismissal asked for while it was
  /// queued closes it after this frame.
  void _markShown() {
    if (_isShown) return;
    _isShown = true;
    if (_closeOnceShown) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  /// Completes once the message has left the screen, saying why:
  /// [SnackBarClosedReason.action] when Undo was used.
  Future<SnackBarClosedReason> get closed => _controller.closed;

  /// Takes the message down, so that its Undo cannot be used once what it
  /// offered to take back is gone for good. Nothing once it has closed.
  ///
  /// Safe from `dispose` or a notification during a build: the bar then
  /// goes after the frame, since closing it rebuilds the messenger.
  void dismiss() {
    _closeOnceShown = true;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      _close();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    // The messenger asserts the bar is the one on screen: a bar already
    // replaced by a newer message has closed, or is closing on its own; a
    // bar still queued closes once shown. A messenger torn down with the
    // app has taken its bars with it.
    if (_isOpen && _isShown && _messenger.mounted) _controller.close();
  }
}

/// Reports, once, that the bar holding it has been built on screen.
class _OnShown extends StatefulWidget {
  const _OnShown({required this.onShown, required this.child});

  final VoidCallback? onShown;
  final Widget child;

  @override
  State<_OnShown> createState() => _OnShownState();
}

class _OnShownState extends State<_OnShown> {
  @override
  void initState() {
    super.initState();
    widget.onShown?.call();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
