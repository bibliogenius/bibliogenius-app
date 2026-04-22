import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/book_sort.dart';

/// Persists the user's library sort preference (field + direction).
///
/// The preference is global to the app: it drives the default ordering of
/// every library view. Manual drag-and-drop reordering is a separate,
/// per-shelf mode handled inside `book_list_screen.dart` via `shelf_position`.
class SortPreferenceProvider extends ChangeNotifier {
  static const _keySortBy = 'library_sort_by';
  static const _keySortDir = 'library_sort_dir';

  SortBy _sortBy = SortBy.author;
  SortDir _sortDir = SortDir.asc;
  bool _loaded = false;

  SortBy get sortBy => _sortBy;
  SortDir get sortDir => _sortDir;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawBy = prefs.getString(_keySortBy);
    final rawDir = prefs.getString(_keySortDir);
    _sortBy = _parseSortBy(rawBy);
    _sortDir = _parseSortDir(rawDir);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSortBy(SortBy value) async {
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

  Future<void> toggleDirection() async {
    await setSortDir(_sortDir == SortDir.asc ? SortDir.desc : SortDir.asc);
  }

  static SortBy _parseSortBy(String? raw) {
    for (final v in SortBy.values) {
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
