import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A set of shelf uuids kept on this device, under one preference key.
///
/// Local, never in the database and never synced: how a reader looks at
/// their shelves is not library data. Keyed by uuid, which survives a
/// rename. A shelf known only from the books' subjects has no uuid: it gets
/// its row (`shelfWithRow`) before it can be listed here.
class ShelfIdSetStore {
  final String prefKey;

  const ShelfIdSetStore(this.prefKey);

  /// Shelves folded in the shelves tab tree.
  static const collapsed = ShelfIdSetStore('shelf_tree_collapsed');

  /// Shelves whose books read in the order saved by hand.
  static const shelfOrder = ShelfIdSetStore('shelf_order_ids');

  /// Where the sets are kept. Replaced in tests to make storage fail.
  @visibleForTesting
  static Future<SharedPreferences> Function() prefs =
      SharedPreferences.getInstance;

  Future<Set<String>> load() async {
    try {
      return ((await prefs()).getStringList(prefKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('ShelfIdSetStore: could not read $prefKey: $e');
      return {};
    }
  }

  /// Never throws: a choice that cannot be kept still applies on screen.
  Future<void> save(Set<String> ids) async {
    try {
      final list = ids.toList()..sort();
      await (await prefs()).setStringList(prefKey, list);
    } catch (e) {
      debugPrint('ShelfIdSetStore: could not keep $prefKey: $e');
    }
  }
}
