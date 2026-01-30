import 'package:flutter/foundation.dart';

/// Global notifier for book list refresh
/// Allows any screen to trigger a refresh of the book list
class BookRefreshNotifier extends ChangeNotifier {
  int _refreshCount = 0;

  int get refreshCount => _refreshCount;

  /// Trigger a refresh of the book list
  void refresh() {
    _refreshCount++;
    notifyListeners();
  }
}
