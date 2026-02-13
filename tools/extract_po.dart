#!/usr/bin/env dart
/// Extracts translations from translation_service.dart into .po files.
///
/// Usage: dart tools/extract_po.dart
///
/// Generates:
///   assets/i18n/messages.pot  — template (all keys, empty msgstr)
///   assets/i18n/{en,fr,es,de}.po — translations from _localizedValues
///   assets/i18n/it.po — empty template for Italian contributor

import 'dart:io';

void main() {
  final sourceFile = File('lib/services/translation_service.dart');
  if (!sourceFile.existsSync()) {
    stderr.writeln('ERROR: Cannot find lib/services/translation_service.dart');
    stderr.writeln('Run this script from the bibliogenius-app/ directory.');
    exit(1);
  }

  final source = sourceFile.readAsStringSync();

  // Extract each language block from _localizedValues
  final languages = <String, Map<String, String>>{};
  for (final lang in ['en', 'fr', 'es', 'de']) {
    languages[lang] = _extractLanguage(source, lang);
  }

  // Collect all keys (union of all languages)
  final allKeys = <String>{};
  for (final map in languages.values) {
    allKeys.addAll(map.keys);
  }
  final sortedKeys = allKeys.toList()..sort();

  print('Extraction summary:');
  print('  Total unique keys: ${sortedKeys.length}');
  for (final lang in ['en', 'fr', 'es', 'de']) {
    print('  $lang: ${languages[lang]!.length} translations');
  }

  final outDir = Directory('assets/i18n');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Generate messages.pot (template)
  _writePot(sortedKeys, languages['en']!, '${outDir.path}/messages.pot');

  // Generate language .po files
  for (final lang in ['en', 'fr', 'es', 'de']) {
    _writePo(sortedKeys, languages[lang]!, languages['en']!, lang,
        '${outDir.path}/$lang.po');
  }

  // Generate empty Italian .po
  _writePo(sortedKeys, {}, languages['en']!, 'it', '${outDir.path}/it.po');

  print('\nGenerated:');
  print('  assets/i18n/messages.pot');
  for (final lang in ['en', 'fr', 'es', 'de', 'it']) {
    print('  assets/i18n/$lang.po');
  }
}

/// Extracts key-value pairs for a given language from the Dart source.
Map<String, String> _extractLanguage(String source, String lang) {
  // Find the language block: 'lang': {  ...  },  };  or next language
  final blockStart = _findLanguageBlockStart(source, lang);
  if (blockStart == -1) {
    stderr.writeln('WARNING: Could not find language block for "$lang"');
    return {};
  }

  final blockEnd = _findMatchingBrace(source, blockStart);
  if (blockEnd == -1) {
    stderr.writeln('WARNING: Could not find closing brace for "$lang" block');
    return {};
  }

  final block = source.substring(blockStart, blockEnd);
  return _parseEntries(block);
}

/// Finds the opening brace position for a language block.
int _findLanguageBlockStart(String source, String lang) {
  // Look for pattern: 'lang': {
  final pattern = "'$lang': {";
  final idx = source.indexOf(pattern);
  if (idx == -1) return -1;
  return idx + pattern.length; // position right after the opening {
}

/// Finds the matching closing brace, handling nested braces.
int _findMatchingBrace(String source, int start) {
  int depth = 1;
  bool inString = false;
  String? stringChar;

  for (int i = start; i < source.length; i++) {
    final c = source[i];

    if (inString) {
      if (c == '\\') {
        i++; // skip escaped char
        continue;
      }
      if (c == stringChar) {
        inString = false;
      }
      continue;
    }

    if (c == "'" || c == '"') {
      inString = true;
      stringChar = c;
      continue;
    }

    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Parses key-value entries from a Dart map block.
Map<String, String> _parseEntries(String block) {
  final result = <String, String>{};

  // Match patterns like:
  //   'key': 'value',
  //   'key': 'value that spans\n    multiple lines',
  //   'key':
  //       'value on next line',
  // We use a state machine approach to handle multi-line Dart strings properly.

  final lines = block.split('\n');
  String? currentKey;
  StringBuffer? currentValue;
  bool inValue = false;

  for (final line in lines) {
    final trimmed = line.trim();

    if (!inValue) {
      // Look for start of entry: 'key': 'value...' or 'key':
      final keyMatch = RegExp(r"^'([^']+)':\s*").firstMatch(trimmed);
      if (keyMatch != null) {
        currentKey = keyMatch.group(1)!;
        final afterKey = trimmed.substring(keyMatch.end);

        if (afterKey.isEmpty) {
          // Value is on the next line
          currentValue = StringBuffer();
          inValue = true;
          continue;
        }

        // Value starts on this line
        final valueResult = _extractStringValue(afterKey);
        if (valueResult != null) {
          result[currentKey] = valueResult;
          currentKey = null;
        } else {
          // Incomplete string, continues on next line
          currentValue = StringBuffer(afterKey);
          inValue = true;
        }
      }
    } else {
      // Continue collecting multi-line value
      currentValue!.write('\n$trimmed');
      final combined = currentValue.toString().trim();

      // Check if we have a complete string value now
      final valueResult = _extractStringValue(combined);
      if (valueResult != null) {
        result[currentKey!] = valueResult;
        currentKey = null;
        currentValue = null;
        inValue = false;
      }
    }
  }

  return result;
}

/// Extracts a Dart string value, handling escapes.
/// Returns null if the string is not yet complete.
String? _extractStringValue(String s) {
  // Remove trailing comma if present
  final trimmed = s.trim();

  // Must start with a quote
  if (trimmed.isEmpty) return null;
  final quote = trimmed[0];
  if (quote != "'" && quote != '"') return null;

  // Find the matching closing quote, handling escapes
  for (int i = 1; i < trimmed.length; i++) {
    if (trimmed[i] == '\\') {
      i++; // skip escaped character
      continue;
    }
    if (trimmed[i] == quote) {
      // Found closing quote — extract and unescape
      final raw = trimmed.substring(1, i);
      return _unescapeDart(raw);
    }
  }

  return null; // String not yet complete
}

/// Converts Dart escape sequences to plain text.
String _unescapeDart(String s) {
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (s[i] == '\\' && i + 1 < s.length) {
      final next = s[i + 1];
      switch (next) {
        case "'":
          buf.write("'");
          break;
        case '"':
          buf.write('"');
          break;
        case '\\':
          buf.write('\\');
          break;
        case 'n':
          buf.write('\n');
          break;
        case 't':
          buf.write('\t');
          break;
        default:
          buf.write('\\');
          buf.write(next);
      }
      i++;
    } else {
      buf.write(s[i]);
    }
  }
  return buf.toString();
}

/// Escapes a string for use in a PO file msgstr/msgid.
String _escapePo(String s) {
  return s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\t', '\\t');
}

/// Formats a PO entry (msgid or msgstr) with proper multi-line handling.
String _formatPoString(String keyword, String value) {
  final escaped = _escapePo(value);
  // For long strings or strings with \n, use multi-line format
  if (escaped.contains('\\n') && escaped.length > 70) {
    final parts = escaped.split('\\n');
    final buf = StringBuffer('$keyword ""\n');
    for (int i = 0; i < parts.length; i++) {
      final suffix = (i < parts.length - 1) ? '\\n' : '';
      buf.writeln('"${parts[i]}$suffix"');
    }
    return buf.toString().trimRight();
  }
  return '$keyword "$escaped"';
}

/// Writes the .pot template file.
void _writePot(
    List<String> keys, Map<String, String> enMap, String path) {
  final buf = StringBuffer();
  buf.writeln('# BiblioGenius Translation Template');
  buf.writeln('# This file is generated by tools/extract_po.dart');
  buf.writeln('#');
  buf.writeln('msgid ""');
  buf.writeln('msgstr ""');
  buf.writeln('"Content-Type: text/plain; charset=UTF-8\\n"');
  buf.writeln('"Content-Transfer-Encoding: 8bit\\n"');
  buf.writeln('');

  for (final key in keys) {
    final enText = enMap[key];
    if (enText != null) {
      buf.writeln('#. ${_escapePo(enText)}');
    }
    buf.writeln(_formatPoString('msgid', key));
    buf.writeln('msgstr ""');
    buf.writeln('');
  }

  File(path).writeAsStringSync(buf.toString());
}

/// Writes a .po file for a specific language.
void _writePo(List<String> keys, Map<String, String> langMap,
    Map<String, String> enMap, String lang, String path) {
  final buf = StringBuffer();
  buf.writeln('# BiblioGenius — $lang translations');
  buf.writeln('# Generated by tools/extract_po.dart');
  buf.writeln('#');
  buf.writeln('msgid ""');
  buf.writeln('msgstr ""');
  buf.writeln('"Language: $lang\\n"');
  buf.writeln('"Content-Type: text/plain; charset=UTF-8\\n"');
  buf.writeln('"Content-Transfer-Encoding: 8bit\\n"');
  buf.writeln('');

  int translated = 0;
  for (final key in keys) {
    final enText = enMap[key];
    if (enText != null) {
      buf.writeln('#. ${_escapePo(enText)}');
    }
    buf.writeln(_formatPoString('msgid', key));
    final value = langMap[key] ?? '';
    buf.writeln(_formatPoString('msgstr', value));
    if (value.isNotEmpty) translated++;
    buf.writeln('');
  }

  File(path).writeAsStringSync(buf.toString());
  print('  $lang: $translated/${keys.length} translated');
}
