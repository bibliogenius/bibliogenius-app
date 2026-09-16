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

  test('the local city round-trips, the sharing consent does not', () {
    // The city is a local preference: someone restoring a backup expects
    // their city back. The decision to publish it in the public directory
    // is a separate gesture and must be made again on the restored install,
    // never inherited silently from an archive.
    expect(kBackupPrefsWhitelist, contains('hub_local_location_city_id'));
    expect(kBackupPrefsWhitelist, contains('hub_local_location_city_country'));
    expect(kBackupPrefsBlacklist, contains('hub_share_city'));

    const stored = <String, Object?>{
      'hub_local_location_city_id': 2988507,
      'hub_local_location_city_country': 'FR',
      'hub_share_city': true,
    };
    final json = exportWhitelistedPrefs((k) => stored[k]);

    expect(json.contains('"hub_local_location_city_id":2988507'), isTrue);
    expect(json.contains('"hub_local_location_city_country":"FR"'), isTrue);
    expect(
      json.contains('hub_share_city'),
      isFalse,
      reason: 'publication consent must not travel in the archive',
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

    final uses = _scanPrefsSetters(libDir);

    final classified = kBackupPrefsWhitelist.union(kBackupPrefsBlacklist);
    final unclassified = uses.keys
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
        final paths = uses[key]!.paths.map(_relPath).toSet().toList()..sort();
        lines.add('  - "$key" found in:');
        for (final path in paths) {
          lines.add('      $path');
        }
      }
      fail(lines.join('\n'));
    }
  });

  test('every whitelisted key has a type the restore path re-applies', () {
    final libDir = _libDirFromCwd();
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'cannot find lib/ from ${Directory.current.path}',
    );

    // `_applyPrefs` in backup_restore_wizard_screen.dart re-applies String and
    // int only. `exportWhitelistedPrefs` writes any non-null value, so a
    // whitelisted key of any other type lands in the archive and is discarded
    // on restore. Adding the key is not enough: the branch must exist too.
    const restorable = <String>{'setString', 'setInt'};

    final uses = _scanPrefsSetters(libDir);
    final offenders = <String, _KeyUse>{};
    for (final key in kBackupPrefsWhitelist) {
      // Keys written behind a const identifier rather than a literal are
      // invisible to this scan, exactly as they are to the drift test.
      final use = uses[key];
      if (use == null) continue;
      if (use.setters.any((s) => !restorable.contains(s))) {
        offenders[key] = use;
      }
    }

    if (offenders.isNotEmpty) {
      final lines = <String>[
        'Whitelisted keys written with a setter the restore path ignores.',
        'Each would be exported into the .bgbackup archive and then dropped',
        'on restore. Add the matching branch to _applyPrefs in',
        'lib/screens/backup_restore_wizard_screen.dart, or move the key to',
        'kBackupPrefsBlacklist:',
        '',
      ];
      for (final entry in offenders.entries) {
        final setters = entry.value.setters.toList()..sort();
        lines.add('  - "${entry.key}" written with ${setters.join(', ')}:');
        final paths = entry.value.paths.map(_relPath).toSet().toList()..sort();
        for (final path in paths) {
          lines.add('      $path');
        }
      }
      fail(lines.join('\n'));
    }
  });
}

/// One SharedPreferences key as it is written in `lib/`: which setters reach
/// it, and the files they sit in.
class _KeyUse {
  final Set<String> setters = <String>{};
  final List<String> paths = <String>[];
}

/// Memoised result of the last scan, so the two tests above read 328 Dart
/// files once between them rather than once each.
Map<String, _KeyUse>? _scanCache;
String? _scanCacheDir;

/// Walks `lib/` and collects every literal `prefs.setX('key', …)` call.
/// Shared by the two tests above so they cannot drift apart on which files
/// are excluded.
Map<String, _KeyUse> _scanPrefsSetters(Directory libDir) {
  if (_scanCache != null && _scanCacheDir == libDir.path) return _scanCache!;

  final pattern = RegExp(
    r'''(setBool|setInt|setString|setDouble|setStringList)\(\s*['"]([a-zA-Z0-9_]+)['"]''',
  );

  final found = <String, _KeyUse>{};

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
      final use = found.putIfAbsent(match.group(2)!, () => _KeyUse());
      use.setters.add(match.group(1)!);
      use.paths.add(entity.path);
    }
  }

  _scanCacheDir = libDir.path;
  _scanCache = found;
  return found;
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
