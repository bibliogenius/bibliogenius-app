import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the "Not interested" action on EXTERNAL discovery cards
/// (ADR-060 section 4.5).
///
/// External cards have no local book uuid, so the uuid-keyed store cannot
/// absorb them. Entries are namespaced:
///   - `isbn:<isbn13>` whenever the card has an ISBN (survives resolver
///     changes, and suppresses the same book arriving through the other
///     discovery lane);
///   - `series:<source_id>:<ordinal>` for ISBN-less volumes;
///   - `author:<source_id>:<normalized title>` for ISBN-less works.
///
/// Bounded at 500 entries with FIFO eviction (the storage policy requires
/// bounded structures); order is preserved by using a string LIST, not a
/// set. Device-local like its uuid-keyed sibling, and excluded from the
/// ADR-037 backup prefs whitelist for the same reason. If a dismissed book
/// is later added to the library the entry goes inert, which is correct:
/// dismissal targeted the suggestion, not the book.
abstract final class ExternalSuggestionDismissalService {
  /// SharedPreferences key: ordered list of dismissed suggestion keys,
  /// oldest first. Listed in the backup prefs blacklist.
  static const String dismissedKeysKey = 'dismissed_external_suggestion_keys';

  /// FIFO cap: past this size the oldest dismissals are evicted.
  static const int maxEntries = 500;

  /// Dismissed suggestion keys, oldest first.
  static Future<List<String>> loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(dismissedKeysKey) ?? const <String>[];
  }

  /// Persist [key] as dismissed. Re-dismissing moves the entry to the
  /// young end of the FIFO instead of duplicating it.
  static Future<void> dismiss(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = (prefs.getStringList(dismissedKeysKey) ?? const <String>[])
        .where((k) => k != key)
        .toList()
      ..add(key);
    if (keys.length > maxEntries) {
      keys.removeRange(0, keys.length - maxEntries);
    }
    await prefs.setStringList(dismissedKeysKey, keys);
  }

  /// Remove [key] from the dismissed list (the SnackBar "Undo" path).
  static Future<void> restore(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = (prefs.getStringList(dismissedKeysKey) ?? const <String>[])
        .where((k) => k != key)
        .toList();
    await prefs.setStringList(dismissedKeysKey, keys);
  }
}
