import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/shelf_id_set_store.dart';
import '../utils/book_sort.dart';

/// Persists the user's library sort preference (field + direction).
///
/// Field and direction are global to the app: they drive the default
/// ordering of every library view. Beside them, each shelf remembers on
/// this device whether it reads in the order saved by hand
/// ([shelfOrderFor]): saving an order or picking "Shelf order" in a shelf
/// turns it on for that shelf alone, and picking a field there turns it off
/// for that shelf alone. Outside a shelf the list follows the last author or
/// title sort the reader chose (see `book_list_screen.dart`).
class SortPreferenceProvider extends ChangeNotifier {
  static const _keySortBy = 'library_sort_by';
  static const _keySortDir = 'library_sort_dir';

  SortBy _sortBy = SortBy.author;
  SortDir _sortDir = SortDir.asc;
  Set<String> _shelfOrderIds = {};
  bool _loaded = false;

  /// The field of the global sort: never [SortBy.shelf], which is not a
  /// field the reader picks for the library but a per-shelf order.
  SortBy get sortBy => _sortBy;
  SortDir get sortDir => _sortDir;

  /// Whether the books of the shelf [shelfId] read in the order saved by
  /// hand.
  bool shelfOrderFor(String? shelfId) =>
      shelfId != null && _shelfOrderIds.contains(shelfId);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawBy = prefs.getString(_keySortBy);
    final rawDir = prefs.getString(_keySortDir);
    _sortBy = _parseSortBy(rawBy);
    _sortDir = _parseSortDir(rawDir);
    _shelfOrderIds = await ShelfIdSetStore.shelfOrder.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSortBy(SortBy value) async {
    assert(value != SortBy.shelf, 'the shelf order is a flag: setShelfOrder');
    if (_sortBy == value) return;
    _sortBy = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortBy, value.name);
  }

  Future<void> setSortDir(SortDir value) async {
    if (_sortDir == value) return;
    _sortDir = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortDir, value.name);
  }

  /// Turns the saved order of the shelf [shelfId] (its uuid) on or off.
  Future<void> setShelfOrder(String shelfId, bool value) async {
    final changed = value
        ? _shelfOrderIds.add(shelfId)
        : _shelfOrderIds.remove(shelfId);
    if (!changed) return;
    notifyListeners();
    await ShelfIdSetStore.shelfOrder.save(_shelfOrderIds);
  }

  /// Picks a field and a direction for the library, in one notification:
  /// listeners re-sort once, not three times. Picked inside the shelf
  /// [shelfId], it also leaves that shelf's saved order behind, and only
  /// that shelf's.
  Future<void> setFieldSort(SortBy by, SortDir dir, {String? shelfId}) async {
    assert(by != SortBy.shelf, 'the shelf order is a flag: setShelfOrder');
    final dropsOrder = shelfOrderFor(shelfId);
    if (_sortBy == by && _sortDir == dir && !dropsOrder) return;
    _sortBy = by;
    _sortDir = dir;
    if (dropsOrder) _shelfOrderIds.remove(shelfId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortBy, by.name);
    await prefs.setString(_keySortDir, dir.name);
    if (dropsOrder) await ShelfIdSetStore.shelfOrder.save(_shelfOrderIds);
  }

  /// Forgets the shelves outside [known], the uuids of the shelves that
  /// exist now: a shelf deleted from another screen or another device.
  Future<void> retainShelfOrders(Set<String> known) async {
    final before = _shelfOrderIds.length;
    _shelfOrderIds.removeWhere((id) => !known.contains(id));
    if (_shelfOrderIds.length == before) return;
    notifyListeners();
    await ShelfIdSetStore.shelfOrder.save(_shelfOrderIds);
  }

  Future<void> toggleDirection() async {
    await setSortDir(_sortDir == SortDir.asc ? SortDir.desc : SortDir.asc);
  }

  static SortBy _parseSortBy(String? raw) {
    for (final v in SortBy.values) {
      if (v == SortBy.shelf) continue;
      if (v.name == raw) return v;
    }
    return SortBy.author;
  }

  static SortDir _parseSortDir(String? raw) {
    for (final v in SortDir.values) {
      if (v.name == raw) return v;
    }
    return SortDir.asc;
  }
}
