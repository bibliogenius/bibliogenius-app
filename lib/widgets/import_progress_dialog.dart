import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// A modal that shows where a long import has got to, and lets the reader
/// stop it.
///
/// Importing a curated list is one network call PER BOOK, in sequence, each
/// with its own timeout. Before this, the pre-import dialog closed and the
/// screen said nothing at all until a SnackBar appeared, which on a ten-book
/// list is a long silence with no way to tell a slow import from a dead one
/// and no way to back out. Offline it is worse: every book waits out its own
/// timeout before failing.
///
/// The dialog OWNS the task rather than being opened next to it. That is
/// what keeps the two in step: there is no route to pop from a callback, no
/// window where the work has finished and the modal has not, and no way to
/// leave a barrier up if the task throws.
class ImportProgressDialog extends StatefulWidget {
  const ImportProgressDialog({
    super.key,
    required this.total,
    required this.task,
  });

  /// How many books the import will walk. Only used to draw the bar; the
  /// task reports its own total, which wins if the two disagree.
  final int total;

  /// The work. It is handed a progress callback and a cancellation
  /// predicate, and it decides what stopping early returns: a partial import
  /// is a result, not an error.
  final Future<Object?> Function(
    void Function(int done, int total) onProgress,
    bool Function() isCancelled,
  )
  task;

  /// Run [task] behind a modal barrier and return whatever it returns.
  ///
  /// Null when the task threw, which the caller reports its own way.
  static Future<T?> run<T extends Object>(
    BuildContext context, {
    required int total,
    required Future<T?> Function(
      void Function(int done, int total) onProgress,
      bool Function() isCancelled,
    )
    task,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportProgressDialog(total: total, task: task),
    );
  }

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog> {
  int _done = 0;
  late int _total = widget.total;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState: a task that reports its
    // starting position synchronously would otherwise call setState before
    // the state is mounted, and the throw would surface as an import that
    // failed instantly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    Object? outcome;
    try {
      outcome = await widget.task(_report, () => _cancelled);
    } catch (_) {
      // The caller owns the error message; the modal owes only to come down.
      outcome = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  void _report(int done, int total) {
    if (!mounted) return;
    setState(() {
      _done = done;
      _total = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = TranslationService.translate(context, 'importing_collection');
    final counter = '$_done / $_total';

    return PopScope(
      // Backing out with the system gesture would leave the import running
      // with nothing on screen. Cancelling is a button, deliberately.
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One node for the whole status, so a screen reader hears
            // "Importing collection, 3 of 10" rather than two fragments
            // (ADR-061 A2).
            Semantics(
              key: const Key('import-progress-status'),
              // Its own node, not a merge into the dialog: without this the
              // label has nowhere to live and the status is spoken as the
              // two loose fragments it is made of.
              container: true,
              excludeSemantics: true,
              label: '$title, $counter',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Text(counter, style: theme.textTheme.labelMedium),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              // Indeterminate until the first report, so a stalled first
              // lookup does not draw a bar frozen at zero as if finished.
              value: _total > 0 && _done > 0 ? _done / _total : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            // Never disabled once pressed: the loop checks between books, so
            // the wait is bounded by ONE book rather than by the whole list.
            onPressed: _cancelled
                ? null
                : () => setState(() => _cancelled = true),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
        ],
      ),
    );
  }
}
