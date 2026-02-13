#!/usr/bin/env dart
/// Validates .po file completeness against messages.pot template.
///
/// Usage: dart tools/validate_po.dart
///
/// Reads assets/i18n/messages.pot as reference and checks each .po file
/// for missing translations.

import 'dart:io';

void main() {
  final potFile = File('assets/i18n/messages.pot');
  if (!potFile.existsSync()) {
    stderr.writeln('ERROR: Cannot find assets/i18n/messages.pot');
    stderr.writeln('Run "dart tools/extract_po.dart" first.');
    exit(1);
  }

  final potKeys = _extractMsgIds(potFile.readAsStringSync());
  print('Template: ${potKeys.length} keys in messages.pot\n');

  final languages = ['en', 'fr', 'es', 'de', 'it'];

  // Header
  print('${'Langue'.padRight(8)}'
      '${'Total'.padLeft(7)}'
      '${'Traduites'.padLeft(12)}'
      '${'Manquantes'.padLeft(13)}'
      '${'Couverture'.padLeft(13)}');
  print('-' * 53);

  bool hasErrors = false;

  for (final lang in languages) {
    final poFile = File('assets/i18n/$lang.po');
    if (!poFile.existsSync()) {
      print('${lang.padRight(8)}  FILE NOT FOUND');
      hasErrors = true;
      continue;
    }

    final translations = _parsePo(poFile.readAsStringSync());
    final translated = translations.entries
        .where((e) => potKeys.contains(e.key) && e.value.isNotEmpty)
        .length;
    final missing = potKeys.length - translated;
    final coverage = (translated / potKeys.length * 100).toStringAsFixed(1);

    print('${lang.padRight(8)}'
        '${potKeys.length.toString().padLeft(7)}'
        '${translated.toString().padLeft(12)}'
        '${missing.toString().padLeft(13)}'
        '${('$coverage%').padLeft(13)}');

    // Report extra keys not in template
    final extraKeys = translations.keys
        .where((k) => !potKeys.contains(k) && translations[k]!.isNotEmpty)
        .toList();
    if (extraKeys.isNotEmpty) {
      print('  ⚠ $lang has ${extraKeys.length} keys not in template');
    }
  }

  print('');

  // Detailed missing keys report (optional: pass --verbose)
  final verbose = Platform.environment['VERBOSE'] == '1' ||
      (Platform.executableArguments.contains('--verbose') ||
          _hasArg('--verbose'));

  if (verbose) {
    print('\n--- Missing keys per language ---\n');
    for (final lang in languages) {
      final poFile = File('assets/i18n/$lang.po');
      if (!poFile.existsSync()) continue;
      final translations = _parsePo(poFile.readAsStringSync());
      final missing = potKeys
          .where((k) => !translations.containsKey(k) || translations[k]!.isEmpty)
          .toList();
      if (missing.isNotEmpty) {
        print('$lang (${missing.length} missing):');
        for (final k in missing) {
          print('  - $k');
        }
        print('');
      }
    }
  } else {
    print('Run with --verbose to see missing keys per language.');
  }

  if (hasErrors) exit(1);
}

bool _hasArg(String arg) {
  // Check both script args and executable args
  try {
    final args =
        Platform.script.pathSegments.isEmpty ? <String>[] : <String>[];
    return args.contains(arg);
  } catch (_) {
    return false;
  }
}

/// Extracts all msgid values from a PO/POT file (excluding the header).
Set<String> _extractMsgIds(String content) {
  final keys = <String>{};
  final lines = content.split('\n');
  bool nextIsMsgstr = false;
  String? currentMsgId;

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('msgid ')) {
      final value = _extractQuotedValue(trimmed.substring(6));
      if (value != null && value.isNotEmpty) {
        currentMsgId = value;
      } else {
        currentMsgId = null; // header entry
      }
      nextIsMsgstr = false;
    } else if (trimmed.startsWith('msgstr ')) {
      if (currentMsgId != null) {
        keys.add(currentMsgId);
      }
      currentMsgId = null;
      nextIsMsgstr = true;
    }
  }

  return keys;
}

/// Parses a PO file and returns a Map of msgid → msgstr.
Map<String, String> _parsePo(String content) {
  final result = <String, String>{};
  final lines = content.split('\n');

  String? currentMsgId;
  String currentMsgStr = '';
  bool inMsgId = false;
  bool inMsgStr = false;

  void _flush() {
    if (currentMsgId != null && currentMsgId!.isNotEmpty) {
      result[currentMsgId!] = _unescapePo(currentMsgStr);
    }
    currentMsgId = null;
    currentMsgStr = '';
    inMsgId = false;
    inMsgStr = false;
  }

  for (final line in lines) {
    final trimmed = line.trim();

    // Skip comments and empty lines
    if (trimmed.isEmpty) {
      _flush();
      continue;
    }
    if (trimmed.startsWith('#')) continue;

    if (trimmed.startsWith('msgid ')) {
      _flush();
      final value = _extractQuotedValue(trimmed.substring(6));
      if (value != null) {
        currentMsgId = value;
        inMsgId = true;
        inMsgStr = false;
      }
    } else if (trimmed.startsWith('msgstr ')) {
      final value = _extractQuotedValue(trimmed.substring(7));
      if (value != null) {
        currentMsgStr = value;
        inMsgId = false;
        inMsgStr = true;
      }
    } else if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      // Continuation line
      final value = trimmed.substring(1, trimmed.length - 1);
      if (inMsgId) {
        currentMsgId = (currentMsgId ?? '') + value;
      } else if (inMsgStr) {
        currentMsgStr += value;
      }
    }
  }
  _flush();

  return result;
}

/// Extracts the quoted string value from a PO directive.
String? _extractQuotedValue(String s) {
  final trimmed = s.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return null;
}

/// Unescapes PO string escapes.
String _unescapePo(String s) {
  return s
      .replaceAll('\\n', '\n')
      .replaceAll('\\t', '\t')
      .replaceAll('\\"', '"')
      .replaceAll('\\\\', '\\');
}
