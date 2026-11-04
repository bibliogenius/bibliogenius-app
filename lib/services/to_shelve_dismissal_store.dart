import 'package:shared_preferences/shared_preferences.dart';

/// The count of books on no shelf at the moment the reader hid the "to
/// shelve" line of the shelves tab, on this device only.
///
/// The line comes back as soon as the count passes that number; the memory
/// goes when the count reaches zero, so the next book to shelve shows it.
class ToShelveDismissalStore {
  ToShelveDismissalStore._();

  /// Zero when the line was not hidden. Zero too on a storage failure: the
  /// line is then simply shown.
  static Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('to_shelve_dismissed_count') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> dismissAt(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('to_shelve_dismissed_count', count);
    } catch (_) {
      // Not kept: the line comes back at the next launch, nothing is lost.
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('to_shelve_dismissed_count');
    } catch (_) {
      // Kept: the line stays hidden until the count passes the old number.
    }
  }
}
