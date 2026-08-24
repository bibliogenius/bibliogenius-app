/// Inputs of the external discovery lookups (ADR-060), mapped from the FFI
/// wire structs: what the client may ask the hub resolver, and the
/// library-wide identity index used to filter the answers. Everything here
/// is derived on-device by the Rust side; only anchor ISBNs and a name
/// ever transit.
class DiscoveryLookupInputs {
  final List<DiscoverySeriesLookup> series;
  final List<DiscoveryAuthorLookup> authors;

  /// Library ISBNs (all statuses including wanting), both 10/13 forms.
  final Set<String> libraryIsbns;

  /// Normalized "title|author" keys for every library book.
  final Set<String> libraryTitleAuthorKeys;

  /// The same two index halves restricted to LIKED books (ADR-066), a
  /// strict subset of the two above. Derived Rust-side from the engine's
  /// own `is_liked`, never re-derived here: the repository read path
  /// overlays `borrowed` and `lent` onto `reading_status` for display, so
  /// a client-side derivation would stop counting a borrowed book that
  /// was read (ADR-059 names that overlay as a corruption source).
  ///
  /// Optional with an empty default so an older payload, or a test that
  /// does not care, simply reports no liked overlap.
  final Set<String> likedIsbns;
  final Set<String> likedTitleAuthorKeys;

  const DiscoveryLookupInputs({
    required this.series,
    required this.authors,
    required this.libraryIsbns,
    required this.libraryTitleAuthorKeys,
    this.likedIsbns = const {},
    this.likedTitleAuthorKeys = const {},
  });

  bool get isEmpty => series.isEmpty && authors.isEmpty;

  /// True when the library index carries nothing at all, which is how the
  /// ADR-059 profile floor reaches the client: below it the FFI returns
  /// the empty default, identity index included, and no consumer may run
  /// its membrane against it.
  bool get hasNoIdentity =>
      libraryIsbns.isEmpty && libraryTitleAuthorKeys.isEmpty;
}

/// One "complete the series" lookup: anchors identify the series, the
/// member identity lets the client match returned volumes against owned
/// ones (source ordinals are truth; local volume numbers are never used).
class DiscoverySeriesLookup {
  /// Local collection id: throttle/cache key, never sent to the hub.
  final String collectionId;

  /// User-authored series name, sent as an opaque tiebreaker.
  final String name;

  /// Up to 3 checksum-valid member ISBNs (canonical ISBN-13).
  final List<String> anchorIsbns;

  /// All member ISBNs in both ISBN-10/13 forms.
  final Set<String> memberIsbns;

  /// Normalized "title|author" keys of the members.
  final Set<String> memberTitleAuthorKeys;

  const DiscoverySeriesLookup({
    required this.collectionId,
    required this.name,
    required this.anchorIsbns,
    required this.memberIsbns,
    required this.memberTitleAuthorKeys,
  });
}

/// One "complete the author" lookup (ADR-060 second lane; consumed by the
/// author-completion iteration, carried through the FFI already).
class DiscoveryAuthorLookup {
  final String name;
  final List<String> anchorIsbns;

  const DiscoveryAuthorLookup({required this.name, required this.anchorIsbns});
}
