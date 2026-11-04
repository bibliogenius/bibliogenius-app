import 'dart:convert';
import 'dart:io';

import 'package:bibliogenius/services/backup_prefs_whitelist.dart';
import 'package:bibliogenius/services/shelf_id_set_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('the contact audience travels with the contact card', () {
    // Both answer "what do I share, and with whom". Restoring the card
    // without its audience would fall back to the legacy default (both
    // audiences on) and could widen who receives it.
    expect(kBackupPrefsWhitelist, contains('hub_contact_info'));
    expect(kBackupPrefsWhitelist, contains('hub_contact_audience'));
  });

  test('the shelves that follow their own order survive a restore', () async {
    // A list of strings: exported as a JSON array, it must come back as one.
    expect(kBackupPrefsWhitelist, contains('shelf_order_ids'));
    SharedPreferences.setMockInitialValues({
      'shelf_order_ids': ['u1', 'u2'],
      'themeStyle': 'dark',
    });
    final source = await SharedPreferences.getInstance();
    final json = exportWhitelistedPrefs(source.get);

    SharedPreferences.setMockInitialValues({});
    final target = await SharedPreferences.getInstance();
    await applyWhitelistedPrefs(json, target);

    expect(target.getStringList('shelf_order_ids'), ['u1', 'u2']);
    expect(target.getString('themeStyle'), 'dark');
  });

  /// Restores [archive] (key to value, as `prefs.json` holds them) onto an
  /// empty store and returns it.
  Future<SharedPreferences> restore(Map<String, Object> archive) async {
    SharedPreferences.setMockInitialValues({});
    final target = await SharedPreferences.getInstance();
    await applyWhitelistedPrefs(jsonEncode(archive), target);
    return target;
  }

  test('a list under a string key is ignored on restore', () async {
    // Restored as a list, the theme would make its reader throw at every
    // launch.
    final target = await restore({'themeStyle': ['dark'], 'country': 'FR'});
    expect(target.get('themeStyle'), isNull);
    expect(target.getString('country'), 'FR');
  });

  test('an integer under a string key is ignored on restore', () async {
    final target = await restore({'themeStyle': 3});
    expect(target.get('themeStyle'), isNull);
  });

  test('a string under the list key is ignored on restore', () async {
    final target = await restore({'shelf_order_ids': 'u1'});
    expect(target.get('shelf_order_ids'), isNull);
  });

  test('the city id restores as an integer', () async {
    final target = await restore({'hub_local_location_city_id': 2988507});
    expect(target.getInt('hub_local_location_city_id'), 2988507);
  });

  test('the shelf order store writes the key declared as a list', () {
    // Written through a field of the store, invisible to the scan below.
    const key = ShelfIdSetStore.shelfOrder;
    expect(kBackupPrefsWhitelist, contains(key.prefKey));
    expect(backupPrefType(key.prefKey), BackupPrefType.stringList);
  });

  test('the shelf orders the store keeps survive a restore', () async {
    // Through the store itself, so that a store writing another type than
    // the declared one fails here.
    SharedPreferences.setMockInitialValues({});
    ShelfIdSetStore.prefs = SharedPreferences.getInstance;
    await ShelfIdSetStore.shelfOrder.save({'u2', 'u1'});
    final json = exportWhitelistedPrefs(
      (await SharedPreferences.getInstance()).get,
    );

    SharedPreferences.setMockInitialValues({});
    await applyWhitelistedPrefs(json, await SharedPreferences.getInstance());

    expect(await ShelfIdSetStore.shelfOrder.load(), {'u1', 'u2'});
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

  test('the hidden "to shelve" count travels as an integer', () async {
    expect(kBackupPrefsWhitelist, contains('to_shelve_dismissed_count'));
    expect(kBackupPrefsBlacklist, isNot(contains('to_shelve_dismissed_count')));
    expect(backupPrefType('to_shelve_dismissed_count'), BackupPrefType.integer);
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

  test('every whitelisted key is written with the type it declares', () {
    final libDir = _libDirFromCwd();
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'cannot find lib/ from ${Directory.current.path}',
    );

    // `applyWhitelistedPrefs` applies a value only when its type is the
    // one `kBackupPrefsTypes` declares for its key (a string by default).
    // A declaration that disagrees with the setter the code uses would drop
    // the key on every restore; a setter with no restorable type at all
    // (bool, double) has no declaration to give.
    const declared = <String, BackupPrefType>{
      'setString': BackupPrefType.string,
      'setInt': BackupPrefType.integer,
      'setStringList': BackupPrefType.stringList,
    };

    final literal = _scanPrefsSetters(libDir);
    final viaConst = _scanConstKeySetters(libDir);
    final offenders = <String, _KeyUse>{};
    for (final key in kBackupPrefsWhitelist) {
      // A key written through a field rather than a literal or a const of
      // its own file stays invisible here: see the shelf order test above.
      for (final use in [literal[key], viaConst[key]]) {
        if (use == null) continue;
        if (use.setters.any((s) => declared[s] != backupPrefType(key))) {
          offenders[key] = use;
        }
      }
    }

    if (offenders.isNotEmpty) {
      final lines = <String>[
        'Whitelisted keys written with a type other than the declared one.',
        'Each would be exported into the .bgbackup archive and then dropped',
        'on restore. Declare its type in kBackupPrefsTypes',
        '(lib/services/backup_prefs_whitelist.dart), or move the key to',
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

/// Every `prefs.setX(ident, …)` whose `ident` is a string const of the same
/// file (`const String _kKey = 'key';`), by key. Used by the type test only:
/// the classification test keeps to literals. Identifiers are matched by
/// name within the file: a parameter named like one of its string consts
/// would be taken for it.
Map<String, _KeyUse> _scanConstKeySetters(Directory libDir) {
  final constDecl = RegExp(
    r'''const\s+(?:String\s+)?(\w+)\s*=\s*['"]([a-zA-Z0-9_]+)['"]''',
  );
  final setter = RegExp(
    r'''(setBool|setInt|setString|setDouble|setStringList)'''
    r'''\(\s*([A-Za-z_]\w*)\s*,''',
  );
  final found = <String, _KeyUse>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/lib/src/rust/')) continue;
    final src = entity.readAsStringSync();
    final consts = {
      for (final m in constDecl.allMatches(src)) m.group(1)!: m.group(2)!,
    };
    for (final match in setter.allMatches(src)) {
      final key = consts[match.group(2)];
      if (key == null) continue;
      final use = found.putIfAbsent(key, () => _KeyUse());
      use.setters.add(match.group(1)!);
      use.paths.add(entity.path);
    }
  }
  return found;
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
