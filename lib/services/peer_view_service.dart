import 'package:dio/dio.dart';

import '../models/book.dart';
import 'api_service.dart';

/// What another library actually receives when it pulls this catalogue.
class PeerViewSnapshot {
  final List<Book> books;

  /// Base the relative cover paths in [books] resolve against, exactly as a
  /// peer resolves them against the URL it dialled.
  final String baseUrl;

  const PeerViewSnapshot({required this.books, required this.baseUrl});

  /// Absolute cover URL for [book], or null when the peer would get nothing.
  String? coverUrlFor(Book book) {
    final raw = book.rawCoverUrl;
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('/') ? '$baseUrl$raw' : raw;
  }
}

/// Reads the library through the peer-facing door, so the app can show the
/// owner what a paired device or a LAN visitor really sees.
///
/// A peer syncs a catalogue with a single unauthenticated `GET /api/books`
/// against this device's HTTP server (`api/peer/sync.rs`), no query parameters.
/// The Rust handler is the only place that decides what leaves the library:
/// with no owner token it drops `private` rows, then runs `redact_for_peer` on
/// the survivors (`api/books.rs`). This service issues that very same request
/// instead of re-deriving the rule in Dart, because a preview that diverges
/// from what is actually published would be worse than no preview at all.
///
/// This is the one place where local HTTP is not the legacy debt architecture
/// Rule F3 warns about. The FFI surface answers the owner's own question ("what
/// is in my library?") and cannot answer this one; being a peer is the only way
/// to see what a peer sees. The route is peer-facing by design and therefore
/// sits outside the ADR-051 owner-only guard, so nothing here loosens it.
abstract final class PeerViewService {
  /// Fetches the peer-visible catalogue.
  ///
  /// Deliberately sends no `Authorization` header: a token would flip the
  /// handler into owner mode and the preview would silently start showing
  /// private books and personal annotations that no peer ever receives.
  static Future<PeerViewSnapshot> fetch() async {
    await ApiService.ensureServerRunning();

    final baseUrl = 'http://127.0.0.1:${ApiService.httpPort}';
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    final response = await dio.get<Map<String, dynamic>>('/api/books');
    final raw = response.data?['books'];
    final books = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(Book.fromJson)
              .toList(growable: false)
        : const <Book>[];

    return PeerViewSnapshot(books: books, baseUrl: baseUrl);
  }
}
