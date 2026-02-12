/// A cover candidate from an external source.
class CoverCandidate {
  final String url;
  final String source; // "Inventaire", "OpenLibrary", "BNF", "Google Books"

  const CoverCandidate({required this.url, required this.source});
}
