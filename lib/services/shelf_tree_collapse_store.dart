import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shelves folded in the shelves tab tree, on this device only.
///
/// A local preference, never in the database and never synced: how a reader
/// looks at their tree is not library data. Keyed by the shelf's uuid, which
/// survives a rename. Only a shelf with sub-shelves can be folded, and a
/// shelf known only from the books' subjects never has any, so every key is
/// a real row's uuid.
class ShelfTreeCollapseStore {
  ShelfTreeCollapseStore._();

  static const prefKey = 'shelf_tree_collapsed';

  /// Where the set is kept. Replaced in tests to make storage fail.
  @visibleForTesting
  static Future<SharedPreferences> Function() prefs =
      SharedPreferences.getInstance;

  static Future<Set<String>> load() async {
    try {
      return ((await prefs()).getStringList(prefKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('ShelfTreeCollapseStore: could not read folded shelves: $e');
      return {};
    }
  }

  /// Never throws: a fold that cannot be kept still folds the tree on
  /// screen.
  static Future<void> save(Set<String> collapsedIds) async {
    try {
      final list = collapsedIds.toList()..sort();
      await (await prefs()).setStringList(prefKey, list);
    } catch (e) {
      debugPrint('ShelfTreeCollapseStore: could not keep folded shelves: $e');
    }
  }
}
