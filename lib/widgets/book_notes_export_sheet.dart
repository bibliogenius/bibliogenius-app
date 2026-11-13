import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_note.dart';
import '../services/translation_service.dart';
import '../utils/book_notes_text.dart';
import '../utils/share_origin.dart';

/// Last export format the reader picked. A habit of this device, not library
/// data: classified in the backup blacklist (`backup_prefs_whitelist.dart`).
const kBookNotesExportFormatPrefKey = 'book_notes_export_format';

/// "Share" is offered where the system share sheet takes text: iOS, Android
/// and macOS. Windows and Linux only get "Copy".
bool get bookNotesShareSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Bottom sheet that exports every note of one book, in plain text or
/// Markdown, to the clipboard or the system share sheet.
class BookNotesExportSheet extends StatefulWidget {
  final String title;
  final String? author;

  /// In the order the notes screen shows them; the export keeps it.
  final List<BookNote> notes;

  const BookNotesExportSheet({
    super.key,
    required this.title,
    this.author,
    required this.notes,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? author,
    required List<BookNote> notes,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => BookNotesExportSheet(
        title: title,
        author: author,
        notes: List.unmodifiable(notes),
      ),
    );
  }

  @override
  State<BookNotesExportSheet> createState() => _BookNotesExportSheetState();
}

class _BookNotesExportSheetState extends State<BookNotesExportSheet> {
  BookNotesExportFormat _format = BookNotesExportFormat.plainText;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    _loadFormat();
  }

  Future<void> _loadFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kBookNotesExportFormatPrefKey);
    final format = BookNotesExportFormat.values
        .where((f) => f.name == saved)
        .firstOrNull;
    if (format != null && mounted) setState(() => _format = format);
  }

  Future<void> _setFormat(BookNotesExportFormat format) async {
    setState(() => _format = format);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBookNotesExportFormatPrefKey, format.name);
  }

  String get _text => formatBookNotes(
    title: widget.title,
    author: widget.author,
    notes: widget.notes,
    format: _format,
  );

  Future<void> _copy() async {
    // A second tap during the clipboard write would pop twice and close the
    // notes screen behind the sheet.
    if (_copying) return;
    _copying = true;
    final confirmation = TranslationService.translate(
      context,
      'notes_export_copied',
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) navigator.pop();
    messenger?.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _share(BuildContext buttonContext) async {
    // Anchor the popover on the button (required on iPad and macOS).
    final origin = shareOrigin(buttonContext);
    final subject = widget.title.trim().isEmpty ? null : widget.title.trim();
    try {
      await Share.share(_text, subject: subject, sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('BookNotesExportSheet: share failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TranslationService.translate;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                t(context, 'notes_export'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<BookNotesExportFormat>(
              segments: [
                ButtonSegment(
                  value: BookNotesExportFormat.plainText,
                  label: Text(t(context, 'notes_export_plain_text')),
                ),
                ButtonSegment(
                  value: BookNotesExportFormat.markdown,
                  label: Text(t(context, 'notes_export_markdown')),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (s) => _setFormat(s.single),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: Text(t(context, 'notes_export_copy')),
                  ),
                ),
                if (bookNotesShareSupported) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (buttonContext) => OutlinedButton.icon(
                        onPressed: () => _share(buttonContext),
                        icon: const Icon(Icons.share),
                        label: Text(t(context, 'action_share')),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
