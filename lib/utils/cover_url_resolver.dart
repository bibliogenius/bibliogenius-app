/// Single source of truth for "how do we turn a book's stored cover_url
/// into something we can display".
///
/// Before this resolver, the rule was reimplemented in four places: the
/// `Book.coverUrl` getter (local library), `Book.largeCoverUrl` (details
/// screen), `Loan.resolvedCoverUrl`, and `_resolvePeerCoverUrl` on the
/// peer book list screen. Each variant had a slightly different
/// fallback (OpenLibrary M vs L, with or without `?default=false`,
/// passthrough rules, cover-proxy routing), so adding a rule to one
/// site silently drifted from the others.
///
/// This class centralises the decision. It intentionally exposes only
/// static helpers: no state, safe to call from any build method.
class CoverUrlResolver {
  CoverUrlResolver._();

  /// True when [url] is directly fetchable over the Internet.
  ///
  /// Mirrors the Rust-side `cover_url::is_servable_remotely` predicate
  /// that enforces security rule S5 (no local filesystem paths in hub
  /// catalog payloads). When Flutter needs to decide whether a URL can
  /// be handed to `CachedNetworkImage` without extra routing, use this.
  static bool isServableRemotely(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  /// True when [url] is either servable remotely or a well-formed
  /// `/api/...` relative path. LAN peers can resolve the latter against
  /// their own base URL; relay peers cannot, so peer-facing callers
  /// should use [resolveForPeer] instead.
  static bool isServableOnLan(String url) =>
      isServableRemotely(url) || url.startsWith('/api');

  /// Builds the OpenLibrary cover URL for an ISBN-derived fallback.
  ///
  /// `default=false` makes OpenLibrary return 404 for unknown or
  /// malformed ISBNs instead of a 1x1 grey placeholder. A real 404
  /// surfaces the caller's `errorWidget`; the placeholder would hide
  /// it and look broken.
  ///
  /// [large] picks the `-L.jpg` variant (details screens); the default
  /// `-M.jpg` is used for list thumbnails.
  static String? _openLibraryFallback(String? isbn, {bool large = false}) {
    if (isbn == null || isbn.isEmpty) return null;
    final size = large ? 'L' : 'M';
    return 'https://covers.openlibrary.org/b/isbn/$isbn-$size.jpg?default=false';
  }

  /// Resolves a cover URL for display in the owner's own library (or
  /// for any view where the OpenLibrary fallback is desirable).
  ///
  /// Priority: the persisted [coverUrl], then an OpenLibrary fallback
  /// derived from [isbn]. Returns `null` when neither is available so
  /// the caller can show a placeholder.
  static String? resolveForLocal({
    String? coverUrl,
    String? isbn,
    bool large = false,
  }) {
    if (coverUrl != null && coverUrl.isNotEmpty) return coverUrl;
    return _openLibraryFallback(isbn, large: large);
  }

  /// Resolves a cover URL for display of a peer's book.
  ///
  /// Unlike [resolveForLocal], this does NOT fall back to OpenLibrary:
  /// the peer is the authoritative source of their covers, and
  /// substituting a third-party image creates the exact visual
  /// inconsistency the cross-peer cover ticket fixes (uploader sees
  /// their custom cover, visitor sees OpenLibrary's).
  ///
  /// - HTTP(S) URLs pass through (typically hub-hosted thumbnails).
  /// - `/api` relative paths are routed through the local Rust
  ///   cover-proxy so Flutter never opens a direct connection to the
  ///   peer: iOS/macOS ATS + firewall + NAT block direct peer calls in
  ///   practice.
  /// - Anything else (local filesystem path, empty) returns `null` to
  ///   let the caller show a placeholder.
  static String? resolveForPeer({
    required String? coverUrl,
    required String? bookId,
    required String peerUrl,
  }) {
    if (coverUrl == null || coverUrl.isEmpty) return null;
    if (isServableRemotely(coverUrl)) return coverUrl;
    if (coverUrl.startsWith('/api') && bookId != null) {
      final encodedPeerUrl = Uri.encodeQueryComponent(peerUrl);
      return '/api/peers/cover-proxy?peer_url=$encodedPeerUrl&book_id=$bookId';
    }
    return null;
  }
}
