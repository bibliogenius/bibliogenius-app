import 'package:flutter_dotenv/flutter_dotenv.dart';

/// In-memory cache for search results with TTL support
/// Can be disabled via ENABLE_SEARCH_CACHE in .env (useful for debugging)
class SearchCache {
  static final SearchCache _instance = SearchCache._internal();
  factory SearchCache() => _instance;
  SearchCache._internal();

  final Map<String, List<Map<String, dynamic>>> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  final Duration _ttl = const Duration(minutes: 5);

  bool get _isEnabled {
    final enabled = dotenv.env['ENABLE_SEARCH_CACHE'] ?? 'true';
    return enabled.toLowerCase() == 'true';
  }

  /// Get cached results for a query if available and not expired
  List<Map<String, dynamic>>? get(String query) {
    if (!_isEnabled) return null;

    final normalizedQuery = query.toLowerCase().trim();
    
    if (_cache.containsKey(normalizedQuery)) {
      final timestamp = _timestamps[normalizedQuery]!;
      if (DateTime.now().difference(timestamp) < _ttl) {
        return _cache[normalizedQuery];
      }
      // Expired - remove from cache
      _cache.remove(normalizedQuery);
      _timestamps.remove(normalizedQuery);
    }
    return null;
  }

  /// Cache results for a query
  void set(String query, List<Map<String, dynamic>> results) {
    if (!_isEnabled) return;

    final normalizedQuery = query.toLowerCase().trim();
    _cache[normalizedQuery] = results;
    _timestamps[normalizedQuery] = DateTime.now();
  }

  /// Clear all cached results
  void clear() {
    _cache.clear();
    _timestamps.clear();
  }

  /// Clear expired entries only
  void clearExpired() {
    final now = DateTime.now();
    final expiredKeys = _timestamps.entries
        .where((entry) => now.difference(entry.value) >= _ttl)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _timestamps.remove(key);
    }
  }

  /// Get cache statistics (for debugging)
  Map<String, dynamic> getStats() {
    return {
      'enabled': _isEnabled,
      'total_entries': _cache.length,
      'ttl_minutes': _ttl.inMinutes,
    };
  }
}
