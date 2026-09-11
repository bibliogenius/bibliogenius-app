import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/book_filters.dart';

/// Persists the reader's choice on the ownership axis (ADR-063).
///
/// The library remembers this axis and NOT the reading-status one, on
/// purpose. Both are filters, but a status filter hides: reopening the app
/// weeks later still scoped to "reading" shows eight books out of five
/// hundred, and a reader who has forgotten the filter believes the rest is
/// lost. The ownership axis cannot do that, because its widest value shows
/// everything: the worst a forgotten choice does here is show too much, which
/// is recoverable at a glance.
///
/// `null` means "no explicit choice", which is not the same as "library":
/// without one, `resolveOwnershipScope` keeps the historical behaviour where
/// a status filter alone opens every ownership up.
class OwnershipPreferenceProvider extends ChangeNotifier {
  static const _key = 'library_ownership_scope';
  static const _declinedKey = 'library_ownership_declined';

  String? _scope;
  bool _declined = false;
  bool _loaded = false;

  /// The remembered scope, or null when the reader never picked one.
  String? get scope => _scope;
  bool get isLoaded => _loaded;

  /// The reader once answered "I do not own this book" when a status change
  /// asked. One such answer can be a holiday read; from the second book on,
  /// the question also offers to widen the default view instead of asking
  /// again each time, so the offer is gated on this flag.
  bool get hasDeclinedOwnership => _declined;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    // Fails closed: a value this build does not know (a downgrade, a renamed
    // scope) must leave the library on its default view rather than filtering
    // on a string nothing understands.
    _scope = OwnershipScope.values.contains(raw) ? raw : null;
    _declined = prefs.getBool(_declinedKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> markOwnershipDeclined() async {
    if (_declined) return;
    _declined = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_declinedKey, true);
  }

  /// Remembers [value], or forgets the choice entirely when it is null.
  Future<void> setScope(String? value) async {
    final next = OwnershipScope.values.contains(value) ? value : null;
    if (_scope == next) return;
    _scope = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, next);
    }
  }
}
