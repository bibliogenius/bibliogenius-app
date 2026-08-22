import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/collection_repository.dart';
import '../models/collection.dart';
import 'book_refresh_notifier.dart';

/// Caches the favorite book-id set (ADR-064) so cards can check membership
/// in O(1) without a per-item FFI call (Rule F4: caching is Flutter's job).
///
/// Catalogue mutations invalidate the cache through [BookRefreshNotifier],
/// which the mutation sites already ping; a toggle updates the set in place
/// so the marker flips instantly.
///
/// Also owns the one-shot adoption bookkeeping: when the user declines to
/// adopt their manual "favorites-like" collection, the refusal is stored
/// device-locally and the question is never asked again on this device
/// (excluded from ADR-037 backups, like the recommendation dismissals).
class FavoritesProvider extends ChangeNotifier {
  static const String adoptionDeclinedKey = 'favorites_adoption_declined';

  final CollectionRepository _repository;
  final BookRefreshNotifier _bookRefreshNotifier;

  Set<String> _favoriteIds = {};
  bool _stale = true;
  bool _loading = false;
  Future<void>? _inFlight;

  FavoritesProvider(this._repository, this._bookRefreshNotifier) {
    _bookRefreshNotifier.addListener(_markStale);
  }

  /// Current favorite ids, possibly stale until [ensureLoaded] ran.
  Set<String> get favoriteIds => _favoriteIds;

  bool isFavorite(String? bookId) =>
      bookId != null && _favoriteIds.contains(bookId);

  void _markStale() {
    _stale = true;
    // Refresh eagerly: the marker sits on cards that are already on screen,
    // so waiting for the next explicit read would show a stale star.
    ensureLoaded();
  }

  /// Load (or reload after invalidation) the favorite id set. Concurrent
  /// callers await the same pass.
  Future<void> ensureLoaded() {
    if (!_stale && !_loading) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final run = _load();
    _inFlight = run;
    return run;
  }

  Future<void> _load() async {
    _loading = true;
    try {
      final ids = await _repository.getFavoriteBookIds();
      _favoriteIds = ids.toSet();
      _stale = false;
      notifyListeners();
    } finally {
      _loading = false;
      _inFlight = null;
    }
  }

  /// Toggle a book's favorite state. The set is updated from the returned
  /// state so the marker flips instantly; the collection is created lazily
  /// Rust-side on the first marking.
  Future<bool> toggle(String bookId) async {
    final isNowFavorite = await _repository.toggleFavoriteBook(bookId);
    if (isNowFavorite) {
      _favoriteIds.add(bookId);
    } else {
      _favoriteIds.remove(bookId);
    }
    notifyListeners();
    return isNowFavorite;
  }

  /// The manual collection to propose for one-shot adoption before the
  /// first favorite marking, or null when none qualifies or the user
  /// already declined on this device.
  Future<Collection?> adoptionCandidate() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(adoptionDeclinedKey) ?? false) return null;
    return _repository.getFavoritesAdoptionCandidate();
  }

  /// Adopt [collection] as THE favorites collection: its members become
  /// favorites immediately.
  Future<void> adopt(Collection collection) async {
    await _repository.adoptFavoritesCollection(collection.id);
    _stale = true;
    await ensureLoaded();
  }

  /// Remember the user's refusal: the adoption question is never asked
  /// again on this device.
  Future<void> declineAdoption() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(adoptionDeclinedKey, true);
  }

  @override
  void dispose() {
    _bookRefreshNotifier.removeListener(_markStale);
    super.dispose();
  }
}
