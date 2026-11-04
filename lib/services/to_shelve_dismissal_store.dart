import 'package:shared_preferences/shared_preferences.dart';

/// The count of books on no shelf at the moment the reader hid the "to
/// shelve" line of the shelves tab, on this device only.
///
/// The line comes back only once the count passes that number. Nothing here
/// reacts to a lower count: the core answers zero on any error, and one failed
/// read must not bring back a line the reader hid.
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
}
