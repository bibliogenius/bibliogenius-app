import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/book_sort.dart';

/// Persists the user's library sort preference (field + direction).
///
/// The preference is global to the app: it drives the default ordering of
/// every library view. Saving a drag-and-drop order on a shelf raises
/// [shelfOrder] beside it, without touching field or direction: inside a
/// shelf the saved order wins, everywhere else the list follows the last
/// author or title sort the reader chose (see `book_list_screen.dart`).
class SortPreferenceProvider extends ChangeNotifier {
  static const _keySortBy = 'library_sort_by';
  static const _keySortDir = 'library_sort_dir';
  static const _keyShelfOrder = 'library_shelf_order';

  SortBy _sortBy = SortBy.author;
  SortDir _sortDir = SortDir.asc;
  bool _shelfOrder = false;
  bool _loaded = false;

  /// The field of the global sort: never [SortBy.shelf], which is not a
  /// field the reader picks for the library but a per-shelf order.
  SortBy get sortBy => _sortBy;
  SortDir get sortDir => _sortDir;

  /// Whether the books of an open shelf read in the order saved by hand.
  bool get shelfOrder => _shelfOrder;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawBy = prefs.getString(_keySortBy);
    final rawDir = prefs.getString(_keySortDir);
    _sortBy = _parseSortBy(rawBy);
    _sortDir = _parseSortDir(rawDir);
    _shelfOrder = prefs.getBool(_keyShelfOrder) ?? false;
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

  Future<void> setShelfOrder(bool value) async {
    if (_shelfOrder == value) return;
    _shelfOrder = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShelfOrder, value);
  }

  /// Picks a field and a direction for the library, leaving any saved shelf
  /// order behind, in one notification: listeners re-sort once, not three
  /// times.
  Future<void> setFieldSort(SortBy by, SortDir dir) async {
    assert(by != SortBy.shelf, 'the shelf order is a flag: setShelfOrder');
    if (_sortBy == by && _sortDir == dir && !_shelfOrder) return;
    _sortBy = by;
    _sortDir = dir;
    _shelfOrder = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortBy, by.name);
    await prefs.setString(_keySortDir, dir.name);
    await prefs.setBool(_keyShelfOrder, false);
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
