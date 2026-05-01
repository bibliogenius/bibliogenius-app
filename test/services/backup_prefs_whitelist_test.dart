import 'dart:io';

import 'package:bibliogenius/services/backup_prefs_whitelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportWhitelistedPrefs round-trips the three v1 keys', () {
    const stored = <String, Object?>{
      'themeStyle': 'dark',
      'languageCode': 'fr',
      'country': 'FR',
      // Should be ignored: not in the whitelist.
      'libraryName': 'Federico\'s Library',
      // Should be ignored: null value.
      'extraThatDoesNotExist': null,
    };

    final json = exportWhitelistedPrefs((k) => stored[k]);

    expect(json.contains('"themeStyle":"dark"'), isTrue);
    expect(json.contains('"languageCode":"fr"'), isTrue);
    expect(json.contains('"country":"FR"'), isTrue);
    expect(
      json.contains('libraryName'),
      isFalse,
      reason: 'non-whitelisted keys must not leak into the archive',
    );
  });

  test('whitelist and blacklist do not overlap', () {
    final overlap = kBackupPrefsWhitelist.intersection(kBackupPrefsBlacklist);
    expect(
      overlap,
      isEmpty,
      reason:
          'a key cannot be both reviewed-as-meaningful and reviewed-as-skip',
    );
  });

  test('drift: every literal prefs.setX(...) key in lib/ is classified', () {
    final libDir = _libDirFromCwd();
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'cannot find lib/ from ${Directory.current.path}',
    );

    final pattern = RegExp(
      r'''(setBool|setInt|setString|setDouble|setStringList)\(\s*['"]([a-zA-Z0-9_]+)['"]''',
    );

    final foundKeys = <String, List<String>>{};

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      // Skip generated FFI bindings and the whitelist file itself; the
      // generated file mints SharedPreferences keys for setUp but they
      // are not real production prefs, and the whitelist file's literals
      // are already the source of truth being checked against.
      if (entity.path.contains('/lib/src/rust/')) continue;
      if (entity.path.endsWith('backup_prefs_whitelist.dart')) continue;

      final src = entity.readAsStringSync();
      for (final match in pattern.allMatches(src)) {
        final key = match.group(2)!;
        foundKeys.putIfAbsent(key, () => []).add(entity.path);
      }
    }

    final classified = kBackupPrefsWhitelist.union(kBackupPrefsBlacklist);
    final unclassified = foundKeys.keys
        .where((k) => !classified.contains(k))
        .toList(growable: false);

    if (unclassified.isNotEmpty) {
      final lines = <String>[
        'Unclassified SharedPreferences keys found in lib/. Each must be added',
        'to either kBackupPrefsWhitelist (user-meaningful, restored) or',
        'kBackupPrefsBlacklist (install-specific, dropped) in',
        'lib/services/backup_prefs_whitelist.dart:',
        '',
      ];
      for (final key in unclassified) {
        final paths = foundKeys[key]!.map(_relPath).toSet().toList()..sort();
        lines.add('  - "$key" found in:');
        for (final path in paths) {
          lines.add('      $path');
        }
      }
      fail(lines.join('\n'));
    }
  });
}

/// Resolves the project's `lib/` directory regardless of where the test
/// runner anchors the working directory (project root in `flutter test`,
/// nested in some CI setups).
Directory _libDirFromCwd() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final candidate = Directory('${dir.path}/lib');
    if (candidate.existsSync() &&
        File('${dir.path}/pubspec.yaml').existsSync()) {
      return candidate;
    }
    dir = dir.parent;
  }
  return Directory('${Directory.current.path}/lib');
}

String _relPath(String absolute) {
  final cwd = Directory.current.path;
  return absolute.startsWith(cwd)
      ? absolute.substring(cwd.length + 1)
      : absolute;
}
