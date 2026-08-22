import 'package:shared_preferences/shared_preferences.dart';

/// Stable identifiers for the dashboard "Discover more" suggestions.
///
/// These strings are persisted, so renaming one resurfaces a suggestion the
/// user has already dismissed. Add new ids, never rename existing ones.
abstract final class DiscoverSuggestionIds {
  static const String localWifi = 'local_wifi';
  static const String publicDirectory = 'public_directory';
  static const String readingLanguages = 'reading_languages';

  /// The favorites marker introduction (ADR-064): tells existing users the
  /// star-bookmark toggle exists, without any interstitial.
  static const String favoritesMarker = 'favorites_marker';

  /// Every id known to this build. Only used by the one-shot migration off the
  /// legacy global flag.
  static const Set<String> all = <String>{
    localWifi,
    publicDirectory,
    readingLanguages,
    favoritesMarker,
  };
}

/// Dismissal state for the dashboard "Discover more" suggestions, one entry per
/// suggestion.
///
/// This used to be a single global boolean: closing the section once hid every
/// suggestion for good, including the local-network and reading-languages ones
/// the user may never have seen. State is now keyed by suggestion id, so
/// dismissing one suggestion silences that suggestion only.
abstract final class DiscoverDismissalService {
  static const String dismissedIdsKey = 'dashboard_discover_dismissed_ids';

  /// Legacy global "the whole section is dismissed" flag. Read once, migrated
  /// into [dismissedIdsKey], then removed.
  static const String legacyDismissedAllKey = 'dashboard_discover_dismissed';

  /// Ids the user has dismissed. Migrates the legacy global flag on first read:
  /// someone who closed the old section did express "hide this", so every
  /// suggestion known at migration time stays hidden rather than reappearing.
  static Future<Set<String>> loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(legacyDismissedAllKey) ?? false) {
      final migrated = DiscoverSuggestionIds.all.toList();
      await prefs.setStringList(dismissedIdsKey, migrated);
      await prefs.remove(legacyDismissedAllKey);
      return migrated.toSet();
    }

    return (prefs.getStringList(dismissedIdsKey) ?? const <String>[]).toSet();
  }

  /// Persists [id] as dismissed and returns the resulting set, so the caller can
  /// drop it straight into `setState` without a second read.
  static Future<Set<String>> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        (prefs.getStringList(dismissedIdsKey) ?? const <String>[]).toSet()
          ..add(id);
    await prefs.setStringList(dismissedIdsKey, dismissed.toList());
    return dismissed;
  }
}
