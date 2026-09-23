// Guard: every `IconButton` in the UI layers carries a tooltip.
//
// An icon-only button has no text node, so a screen reader announces nothing
// at all without one (Rule A1). Seven of them had shipped that way, including
// the show/hide toggle on the backup passphrase and the play/pause of the
// audio player.
//
// The guard also rejects an EMPTY tooltip. `tooltip: ''` reads as compliant to
// any scan looking for the argument, but it suppresses the localized fallback
// Flutter would otherwise supply, which is strictly worse than leaving the
// argument out. A collection screen shipped exactly that.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UI layers only: nothing under `lib/services` or `lib/data` builds widgets.
const _scanned = ['lib/screens', 'lib/widgets', 'lib/utils', 'lib/audio'];

/// The rule is deliberately narrow: the name rides on the button's own
/// `tooltip`, never on a `Tooltip` or `Semantics` wrapper around it. Every one
/// of the app's IconButtons already reads that way, so an allowance for the
/// wrapper form would excuse nothing today while leaving a hole for a mute
/// button whose neighbour happens to carry a wrapper.
final _iconButton = RegExp(
  r'\bIconButton(?:\.filled|\.filledTonal|\.outlined)?\s*\(',
);
final _emptyTooltip = RegExp(r'''\btooltip\s*:\s*(''|"")''');

/// Index of the `)` closing the `(` at [open], skipping strings and comments.
int _matchingParen(String src, int open) {
  var depth = 0;
  String? inString;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (inString != null) {
      if (c == '\\') {
        i++;
      } else if (c == inString) {
        inString = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inString = c;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final newline = src.indexOf('\n', i);
      if (newline == -1) return -1;
      i = newline;
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Whether [body] passes [key] as its OWN argument.
///
/// Depth matters: an `icon: Icon(...)` holding a nested widget that itself
/// takes a tooltip would otherwise vouch for the button wrapping it.
///
/// Comments are skipped for the same reason they are in [_matchingParen], and
/// the omission was not theoretical: an apostrophe in ordinary English prose
/// ("the reader's way back") opened a string that swallowed the rest of the
/// body, and a button with a perfectly good tooltip was reported as mute.
bool _hasOwnArgument(String body, String key) {
  final pattern = RegExp('\\b$key\\s*:');
  var depth = 0;
  String? inString;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (inString != null) {
      if (c == '\\') {
        i++;
      } else if (c == inString) {
        inString = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inString = c;
      continue;
    }
    if (c == '/' && i + 1 < body.length && body[i + 1] == '/') {
      final newline = body.indexOf('\n', i);
      if (newline == -1) break;
      i = newline;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      continue;
    }
    if (depth == 0 && pattern.matchAsPrefix(body, i) != null) return true;
  }
  return false;
}

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('every IconButton names itself for a screen reader', () {
    final offenders = <String>[];
    var sites = 0;

    for (final dir in _scanned) {
      for (final file in _dartFiles(dir)) {
        final source = file.readAsStringSync();
        for (final match in _iconButton.allMatches(source)) {
          final open = match.end - 1;
          final close = _matchingParen(source, open);
          if (close == -1) continue;
          sites++;
          final body = source.substring(open + 1, close);
          if (_hasOwnArgument(body, 'tooltip')) continue;
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }

    // A floor, so a scanner that silently stops matching cannot pass by
    // finding nothing at all.
    expect(
      sites,
      greaterThan(100),
      reason: 'only $sites IconButton sites found, the scan looks broken',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'every IconButton carries its own translated `tooltip`; a `Tooltip` '
          'or `Semantics` wrapper around it does not count:'
          '\n${offenders.join('\n')}',
    );
  });

  test('no IconButton silences its tooltip with an empty string', () {
    final offenders = <String>[];

    for (final dir in _scanned) {
      for (final file in _dartFiles(dir)) {
        final source = file.readAsStringSync();
        for (final match in _emptyTooltip.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'an empty tooltip suppresses the localized default, drop the '
          'argument or translate it:\n${offenders.join('\n')}',
    );
  });
}
