import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../providers/metadata_fill_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../widgets/app_snack_bar.dart';

/// What the reader decided when the file names no ISBN column: give up, import
/// without ISBN, or point at the column that carries one.
typedef _MissingIsbnChoice = ({bool goOn, int? column});

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
      Future<Response> import({
        required bool allowMissingIsbn,
        int? isbnColumnIndex,
      }) => kIsWeb
          ? apiService.importBooks(
              file.bytes!,
              filename: file.name,
              allowMissingIsbn: allowMissingIsbn,
              isbnColumnIndex: isbnColumnIndex,
            )
          : apiService.importBooks(
              file.path!,
              allowMissingIsbn: allowMissingIsbn,
              isbnColumnIndex: isbnColumnIndex,
            );

      var response = await import(allowMissingIsbn: false);

      _hideLoading();
      if (!context.mounted) return;

      if (response.statusCode == 400 &&
          response.data is Map &&
          response.data['error'] == ApiService.importErrorIsbnColumnMissing) {
        final columns = List<String>.from(response.data['columns'] ?? const []);
        final positions = List<int>.from(
          response.data['column_positions'] ?? const [],
        );
        final choice = await _resolveMissingIsbnColumn(
          context,
          columns,
          positions,
        );
        if (!choice.goOn || !context.mounted) return;

        _showLoading(context);
        response = await import(
          allowMissingIsbn: true,
          isbnColumnIndex: choice.column,
        );
        _hideLoading();
        if (!context.mounted) return;
      }

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? importFailedMsg);
      }

      final data = response.data as Map;
      final int imported = data['imported'] ?? 0;
      if (imported > 0) {
        hubDirectory.markCatalogDirty();
        // The banner that offers to repair an import reads a completeness stat
        // and a creation cluster, both measured at startup, when this library
        // was whatever it was before these books existed. Re-read them now, or
        // the offer waits for the next launch.
        unawaited(context.read<MetadataFillProvider>().loadImportSignals());
      }

      // AppSnackBar draws on the theme's container colours, so the text
      // keeps its contrast in both themes; a raw coloured SnackBar did not.
      final message = _outcomeMessage(context, data);
      if (_outcomeIsWarning(data)) {
        // Long enough to read the count and decide, then gone. Without
        // `persist: false` an action pins the bar to the screen until it is
        // tapped or swiped, across every page. The offer it carries is not
        // lost with it: the library banner and the completeness screen both
        // hold it, durably.
        AppSnackBar.error(
          context,
          message,
          action: _outcomeAction(context, data),
          persist: false,
          duration: const Duration(seconds: 12),
        );
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

  /// The reimport offer, shown on an import that produced no ISBN at all. It
  /// is an action rather than a second message: the snackbar already says what
  /// happened, and this is the one thing worth doing about it.
  static SnackBarAction? _outcomeAction(BuildContext context, Map data) {
    if (!_outcomeIsWarning(data)) return null;
    return SnackBarAction(
      label: TranslationService.translate(context, 'reimport_snackbar_action'),
      onPressed: () => completeFromFile(context),
    );
  }

  /// "Reimport to complete" (ADR-071): read the file a second time and fill
  /// what the books already in the library are missing.
  ///
  /// The same readers as the import, with a collecting sink instead of the
  /// book-creating one, so nothing is created here. When no column name says
  /// "ISBN", the reader designates the column, for this run only.
  static Future<void> completeFromFile(BuildContext context) async {
    final apiService = context.read<ApiService>();
    final hubDirectory = context.read<HubDirectoryProvider>();
    final errorPrefix = TranslationService.translate(
      context,
      'migration_error_prefix',
    );
    final failedMsg = TranslationService.translate(
      context,
      'migration_import_failed',
    );

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      if (!context.mounted) return;

      final file = result.files.first;
      final parsed = <frb.FrbBook>[];
      Future<Response> read({int? isbnColumnIndex}) {
        parsed.clear();
        final source = kIsWeb ? file.bytes! : file.path!;
        return apiService.importBooks(
          source,
          filename: file.name,
          // The reader has already been told the file may name no ISBN column
          // (that is what the dialog below is for); a second refusal would only
          // repeat the question.
          allowMissingIsbn: isbnColumnIndex != null,
          isbnColumnIndex: isbnColumnIndex,
          sink: (book) async => parsed.add(book),
        );
      }

      _showLoading(context);
      var response = await read();
      _hideLoading();
      if (!context.mounted) return;

      if (response.statusCode == 400 &&
          response.data is Map &&
          response.data['error'] == ApiService.importErrorIsbnColumnMissing) {
        final columns = List<String>.from(response.data['columns'] ?? const []);
        final positions = List<int>.from(
          response.data['column_positions'] ?? const [],
        );
        final chosen = await _pickIsbnColumn(context, columns, positions);
        if (chosen == null || !context.mounted) return;

        _showLoading(context);
        response = await read(isbnColumnIndex: chosen);
        _hideLoading();
        if (!context.mounted) return;
      }

      if (response.statusCode != 200) {
        // A response with no `error` key would otherwise surface as a bare
        // "Exception:" glued to the prefix, which says nothing at all.
        final detail = response.data is Map ? response.data['error'] : null;
        throw Exception(detail ?? failedMsg);
      }

      final rows = parsed
          .map(
            (b) => frb.FrbImportRow(
              title: b.title,
              author: b.author,
              isbn: b.isbn,
              publisher: b.publisher,
              publicationYear: b.publicationYear,
            ),
          )
          .toList();
      if (rows.isEmpty) {
        AppSnackBar.error(
          context,
          TranslationService.translate(context, 'reimport_no_rows'),
        );
        return;
      }

      _showLoading(context);
      final report = await FfiService().importCompleteFromRows(rows);
      _hideLoading();
      if (!context.mounted) return;

      if (report.completed > 0) {
        // Marking alone only takes effect on the next lifecycle resume, and a
        // campaign that just restored a whole shelf of ISBNs is exactly what
        // the peers should see now.
        hubDirectory
          ..markCatalogDirty()
          ..syncCatalogIfDirty();
        // The repair is done: the banner must stop offering it, on the same
        // signals it appeared on.
        unawaited(context.read<MetadataFillProvider>().loadImportSignals());
      }
      await _showCompletionSummary(context, report);
    } catch (e) {
      _hideLoading();
      if (!context.mounted) return;
      AppSnackBar.error(context, '$errorPrefix : $e');
    }
  }

  /// Ask which column carries the ISBN. Returns the column's position in the
  /// original header row, or null when the reader backs out.
  static Future<int?> _pickIsbnColumn(
    BuildContext context,
    List<String> columns,
    List<int> positions,
  ) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(TranslationService.translate(ctx, 'reimport_pick_column')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TranslationService.translate(ctx, 'reimport_pick_column_body'),
            ),
            const SizedBox(height: 12),
            // A ListTile with an onTap already announces itself as a button
            // carrying its title; wrapping it announces the name twice.
            for (var i = 0; i < columns.length; i++)
              ListTile(
                dense: true,
                title: Text(columns[i]),
                onTap: () =>
                    Navigator.of(ctx).pop(i < positions.length ? positions[i] : i),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
        ],
      ),
    );
  }

  /// The four numbers, the two lists, and the undo. A campaign that completed
  /// nothing says so here rather than behind a success message.
  static Future<void> _showCompletionSummary(
    BuildContext context,
    frb.FrbImportCompletionReport report,
  ) {
    // The screen that opened the sheet: it outlives it, so it is where a
    // message shown after the sheet closes must be posted.
    final host = context;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    TranslationService.translate(ctx, 'reimport_summary_title'),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Text(completionSummaryText(ctx, report)),
                if (report.skipped.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: Text(
                      TranslationService.translate(
                        ctx,
                        'reimport_summary_skipped_list',
                      ),
                    ),
                    children: [
                      // The backend caps this list; the counters above are
                      // exact. Built on demand and inside a bounded box: a
                      // campaign can leave two hundred rows aside, and laying
                      // them all out at once to hide most of them is work
                      // nobody asked for.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: report.skipped.length,
                          itemBuilder: (_, i) {
                            final row = report.skipped[i];
                            return ListTile(
                              dense: true,
                              title: Text(row.title),
                              subtitle: Text(
                                TranslationService.translate(
                                  ctx,
                                  skipReasonKey(row.reason),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Saying "N ambiguous" and showing 200 lines without a
                      // word would read as a wrong count.
                      if (hiddenSkippedRows(report) > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Text(
                            TranslationService.translate(
                              ctx,
                              'reimport_summary_skipped_truncated',
                              params: {'count': '${hiddenSkippedRows(report)}'},
                            ),
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Wrap, not Row: on a narrow sheet "Undo this completion" and
                // "Close" do not share a line, and a Row would squeeze the
                // labels until they read one letter per line.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    if (report.completed > 0)
                      TextButton(
                        onPressed: () async {
                          final n = await FfiService().metadataFillUndoRun(
                            report.batchId,
                          );
                          if (!ctx.mounted) return;
                          // The message is built and shown from the screen
                          // underneath: popping the sheet deactivates `ctx`,
                          // and a snackbar looks up the theme and the
                          // ScaffoldMessenger through the context it is given.
                          final done = TranslationService.translate(
                            ctx,
                            'reimport_undone',
                            params: {'count': '$n'},
                          );
                          Navigator.of(ctx).pop();
                          if (!host.mounted) return;
                          AppSnackBar.success(host, done);
                        },
                        child: Text(
                          TranslationService.translate(ctx, 'reimport_undo'),
                        ),
                      ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(TranslationService.translate(ctx, 'close')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The summary sentence. Public so a test can read it without a screen.
  @visibleForTesting
  static String completionSummaryText(
    BuildContext context,
    frb.FrbImportCompletionReport report,
  ) => TranslationService.translate(
    context,
    'reimport_summary_counts',
    params: {
      'rows': '${report.rowsRead}',
      'completed': '${report.completed}',
      'no_match': '${report.noMatch}',
      'ambiguous': '${report.ambiguous}',
    },
  );

  /// Rows the campaign set aside but did not carry back for display: the
  /// backend caps the sample, the counters stay exact. Public so a test can
  /// check the arithmetic without a screen.
  @visibleForTesting
  static int hiddenSkippedRows(frb.FrbImportCompletionReport report) {
    final total = report.noMatch + report.ambiguous;
    final listed = report.skipped.length;
    return total > listed ? total - listed : 0;
  }

  /// Translation key for a skipped row's reason. Unknown reasons fall back to
  /// "no match": a new reason must never render as a raw wire name.
  @visibleForTesting
  static String skipReasonKey(String reason) => switch (reason) {
    'ambiguous_in_file' => 'reimport_reason_ambiguous_in_file',
    'ambiguous_in_library' => 'reimport_reason_ambiguous_in_library',
    _ => 'reimport_reason_no_match',
  };

  /// Ask, then let the reader designate the column rather than lose it.
  ///
  /// The designation used to belong to the reimport mode alone, which meant a
  /// file naming its column `Code` had to be imported without ISBN and repaired
  /// afterwards. The picker was already there; offering it at the door costs a
  /// button and saves the round trip. Backing out of the picker returns to the
  /// question rather than cancelling the import.
  static Future<_MissingIsbnChoice> _resolveMissingIsbnColumn(
    BuildContext context,
    List<String> columns,
    List<int> positions,
  ) async {
    while (true) {
      if (!context.mounted) return (goOn: false, column: null);
      final answer = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(
            TranslationService.translate(
              ctx,
              'import_isbn_column_missing_title',
            ),
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
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(TranslationService.translate(ctx, 'cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('pick'),
              child: Text(
                TranslationService.translate(ctx, 'import_choose_isbn_column'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('without'),
              child: Text(
                TranslationService.translate(
                  ctx,
                  'import_continue_without_isbn',
                ),
              ),
            ),
          ],
        ),
      );

      if (answer == 'without') return (goOn: true, column: null);
      if (answer != 'pick') return (goOn: false, column: null);
      if (!context.mounted) return (goOn: false, column: null);

      final chosen = await _pickIsbnColumn(context, columns, positions);
      if (chosen != null) return (goOn: true, column: chosen);
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
