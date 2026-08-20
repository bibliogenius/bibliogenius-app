import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the "Not interested" action on recommendations (ADR-059
/// follow-up).
///
/// Dismissals are keyed by book uuid and apply to every recommendation
/// surface (dashboard suggestions, "You might also like" carousel, "See all"
/// screen). They are deliberately device-local `SharedPreferences` state: a
/// CRR table would be disproportionate for a per-device UI preference, and
/// replicating dismissals across devices would need its own ADR.
///
/// The in-memory copy of this set lives in `RecommendationProvider`; this
/// service only owns the storage.
abstract final class RecommendationDismissalService {
  /// SharedPreferences key: string list of dismissed book uuids. Listed in
  /// the backup prefs blacklist (install-local, like the discover dismissals).
  static const String dismissedBookIdsKey =
      'dismissed_recommendation_book_uuids';

  /// Book uuids the user has marked as "Not interested".
  static Future<Set<String>> loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(dismissedBookIdsKey) ?? const <String>[])
        .toSet();
  }

  /// Persist [bookId] as dismissed.
  static Future<void> dismiss(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        (prefs.getStringList(dismissedBookIdsKey) ?? const <String>[]).toSet()
          ..add(bookId);
    await prefs.setStringList(dismissedBookIdsKey, dismissed.toList());
  }

  /// Remove [bookId] from the dismissed set (the SnackBar "Undo" path).
  static Future<void> restore(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        (prefs.getStringList(dismissedBookIdsKey) ?? const <String>[]).toSet()
          ..remove(bookId);
    await prefs.setStringList(dismissedBookIdsKey, dismissed.toList());
  }
}
