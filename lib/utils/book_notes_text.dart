/// Turns the reading notes of one book into text the reader can copy or
/// share, in plain text or Markdown.
library;

import 'dart:math' as math;

import '../models/book_note.dart';

/// The formats a reader can export their notes in.
enum BookNotesExportFormat { plainText, markdown }

/// Formats [notes] under a header made of [title] and [author].
///
/// Notes come out in the order of [notes]: pass the list as the screen shows
/// it. An empty title or author is left out rather than printed as a blank
/// line. In Markdown, every character that Markdown would interpret is
/// escaped, so a note renders exactly as it was typed.
String formatBookNotes({
  required String title,
  String? author,
  required List<BookNote> notes,
  required BookNotesExportFormat format,
}) {
  final cleanTitle = title.trim();
  final cleanAuthor = author?.trim() ?? '';
  final blocks = switch (format) {
    BookNotesExportFormat.plainText => [
      if (cleanTitle.isNotEmpty || cleanAuthor.isNotEmpty)
        [cleanTitle, cleanAuthor].where((s) => s.isNotEmpty).join('\n'),
      for (final note in notes)
        [
          _normalizeLineEndings(note.content),
          if (note.page != null) _pageLabel(note.page!),
        ].join('\n'),
    ],
    BookNotesExportFormat.markdown => [
      if (cleanTitle.isNotEmpty) '# ${_escapeInline(cleanTitle)}',
      if (cleanAuthor.isNotEmpty) '*${_escapeInline(cleanAuthor)}*',
      for (final note in notes) ...[
        _markdownQuote(note.content),
        if (note.page != null) _pageLabel(note.page!),
      ],
    ],
  };
  return '${blocks.join('\n\n')}\n';
}

/// Same label as the note tile shows.
String _pageLabel(int page) => 'p. $page';

String _normalizeLineEndings(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Characters with an inline meaning in CommonMark / GFM. `(` and `)` only
/// matter after a `]`, which is escaped, so they stay readable. `_` is
/// handled apart (see [_flankingUnderscore]).
final _inlineSpecial = RegExp(r'[\\`*\[\]<>#|~&]');

/// An underscore between two letters or digits never opens emphasis in
/// CommonMark; escaping it there would split emails (`a_b@c.fr`) into a
/// wrong mailto autolink. Only the other underscores are escaped.
final _flankingUnderscore = RegExp(
  r'(?<![\p{L}\p{N}])_|_(?![\p{L}\p{N}])',
  unicode: true,
);

/// What GFM autolinks: an explicit `<scheme://...>` (kept as typed) or a
/// bare URL. Escaping inside either would put backslashes into the link
/// target and its visible text.
final _autolinkedUrl = RegExp(
  r'<https?://[^\s<>]*>|(?<![\p{L}\p{N}.])(?:https?://|www\.)[^\s<>]+',
  caseSensitive: false,
  unicode: true,
);

String _escapeInline(String s) {
  String escape(String part) => part
      .replaceAllMapped(_inlineSpecial, (m) => '\\${m[0]}')
      .replaceAllMapped(_flankingUnderscore, (m) => '\\${m[0]}');
  final out = StringBuffer();
  var last = 0;
  for (final url in _autolinkedUrl.allMatches(s)) {
    out
      ..write(escape(s.substring(last, url.start)))
      ..write(url[0]);
    last = url.end;
  }
  out.write(escape(s.substring(last)));
  return out.toString();
}

/// Markers that only mean something at the start of a line: bullet lists and
/// setext / thematic-break underlines (`-`, `+`, `=`), and ordered lists
/// (`12.` or `3)` followed by a space).
final _leadingMarker = RegExp(r'^(\s*)([-+=])');
final _orderedListMarker = RegExp(r'^(\s*\d+)([.)])(?=\s|$)');

/// Four columns of indentation would turn the line into a code block.
/// Markdown drops up to three leading spaces anyway, so capping there
/// changes nothing visible.
final _leadingIndent = RegExp(r'^[ \t]+');

String _capIndent(String line) =>
    line.replaceFirstMapped(_leadingIndent, (m) {
      final width = m[0]!.codeUnits.fold(0, (w, c) => w + (c == 9 ? 4 : 1));
      return ' ' * math.min(width, 3);
    });

bool _endsWithUrl(String line) =>
    _autolinkedUrl.allMatches(line).any((m) => m.end == line.length);

String _escapeLine(String line) => _escapeInline(_capIndent(line))
    .replaceFirstMapped(_leadingMarker, (m) => '${m[1]}\\${m[2]}')
    .replaceFirstMapped(_orderedListMarker, (m) => '${m[1]}\\${m[2]}');

/// One note as a single blockquote. Line breaks are kept with a hard break,
/// and blank lines with a bare `>`, so the note keeps its shape instead of
/// collapsing into one paragraph. The break is a trailing backslash, except
/// after a URL, which would swallow it: two trailing spaces there.
String _markdownQuote(String content) {
  final lines = _normalizeLineEndings(content).split('\n');
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      out.write('>');
    } else {
      out.write('> ${_escapeLine(line)}');
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      if (next != null && next.trim().isNotEmpty) {
        out.write(_endsWithUrl(line) ? '  ' : '\\');
      }
    }
    if (i + 1 < lines.length) out.write('\n');
  }
  return out.toString();
}
