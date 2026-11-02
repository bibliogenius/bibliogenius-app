import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shelves last chosen in a book form, on this device only.
///
/// A local preference, never in the database and never synced: it is a
/// shortcut for the next book, not library data. Updated when a book form
/// is saved; the list is read back by the shelf selector, which drops the
/// names of shelves deleted since.
class RecentShelvesStore {
  RecentShelvesStore._();

  static const prefKey = 'recent_shelf_names';
  static const limit = 5;

  /// Where the list is kept. Replaced in tests to make storage fail.
  @visibleForTesting
  static Future<SharedPreferences> Function() prefs =
      SharedPreferences.getInstance;

  /// Most recent first.
  static Future<List<String>> load() async {
    try {
      return (await prefs()).getStringList(prefKey) ?? const [];
    } catch (e) {
      debugPrint('RecentShelvesStore: could not read recent shelves: $e');
      return const [];
    }
  }

  /// Records [chosen], in the order they were picked: the last one ends up
  /// first. Never throws: callers record after saving a book, and a
  /// shortcut that cannot be kept must not turn that save into a failure.
  static Future<void> record(Iterable<String> chosen) async {
    if (chosen.every((name) => name.trim().isEmpty)) return;
    try {
      final store = await prefs();
      final current = store.getStringList(prefKey) ?? const <String>[];
      await store.setStringList(prefKey, pushRecentShelves(current, chosen));
    } catch (e) {
      debugPrint('RecentShelvesStore: could not record recent shelves: $e');
    }
  }
}

/// [current] with [chosen] pushed to the front, the last chosen first.
///
/// Names compare exactly, after trimming: the database tells shelves apart
/// byte for byte, so "polar" and "Polar" are two shelves and two entries.
/// A shelf chosen again moves up instead of appearing twice. Capped at
/// [RecentShelvesStore.limit], the oldest dropped.
List<String> pushRecentShelves(List<String> current, Iterable<String> chosen) {
  final result = <String>[];
  final seen = <String>{};
  final picked = chosen.map((n) => n.trim()).toList().reversed;
  for (final name in [...picked, ...current.map((n) => n.trim())]) {
    if (name.isEmpty || !seen.add(name)) continue;
    result.add(name);
    if (result.length == RecentShelvesStore.limit) break;
  }
  return result;
}
