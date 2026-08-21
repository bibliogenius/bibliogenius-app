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

  const DiscoveryLookupInputs({
    required this.series,
    required this.authors,
    required this.libraryIsbns,
    required this.libraryTitleAuthorKeys,
  });

  bool get isEmpty => series.isEmpty && authors.isEmpty;
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
