import 'isbn_validator.dart';

/// Anything the book page can link to for one ISBN: a curated registry
/// portal or a user-connected one (custom bookshop, library catalogue).
abstract class BookLinkTarget {
  String get name;

  /// [title] only matters to targets whose template is title-based
  /// (user-connected catalogues); registry portals key on the ISBN.
  Uri? bookUri(String isbn, {String title});
}

/// A collective portal of independent bookshops able to locate a book near
/// the reader from its ISBN alone. Portals handle geolocation on their own
/// site: the app only ever puts the ISBN in the URL, nothing about the
/// reader leaves the device.
class BookshopPortal implements BookLinkTarget {
  final String id;

  /// Proper noun, displayed as-is (not translated).
  @override
  final String name;

  /// ISO 3166-1 alpha-2 country the portal serves.
  final String country;

  /// URL template with a literal `{ean13}` placeholder.
  final String bookUrlTemplate;

  /// Offered on the book card when the reader picked no portal themselves.
  final bool isCountryDefault;

  const BookshopPortal({
    required this.id,
    required this.name,
    required this.country,
    required this.bookUrlTemplate,
    this.isCountryDefault = false,
  });

  /// Deep link to this portal's page for [isbn], or null when it cannot
  /// be normalised to EAN-13 (portals reject ISBN-10 and free text).
  @override
  Uri? bookUri(String isbn, {String title = ''}) {
    final ean13 = IsbnValidator.toIsbn13(isbn);
    if (ean13 == null) return null;
    final uri = Uri.tryParse(bookUrlTemplate.replaceFirst('{ean13}', ean13));
    if (uri == null || uri.scheme != 'https') return null;
    return uri;
  }
}

/// Inclusion criterion: collective portals of independent bookshops
/// (national or regional), never single retail chains, so exclusion is
/// structural rather than a blacklist. Each URL template is verified
/// empirically against the live portal (hit, unknown ISBN, ISBN-10
/// rejection) before the entry lands here; last sweep 2026-08-28.
const List<BookshopPortal> bookshopPortalRegistry = [
  BookshopPortal(
    id: 'placedeslibraires',
    name: 'Place des libraires',
    country: 'FR',
    // EAN-only URL 301s to the canonical slugged page; unknown ISBN 404s
    // to their advanced-search page.
    bookUrlTemplate: 'https://www.placedeslibraires.fr/livre/{ean13}',
    isCountryDefault: true,
  ),
  BookshopPortal(
    id: 'leslibraires-fr',
    name: 'Les Libraires',
    country: 'FR',
    // Search redirects straight to the book page on a hit; unknown ISBN
    // lands on an empty result page, never a 404.
    bookUrlTemplate: 'https://www.leslibraires.fr/recherche?q={ean13}',
  ),
  BookshopPortal(
    id: 'librairiesindependantes',
    name: 'Librairies indépendantes',
    country: 'FR',
    // Unknown ISBN degrades to a generic page, never a 404.
    bookUrlTemplate: 'https://www.librairiesindependantes.com/product/{ean13}/',
  ),
  BookshopPortal(
    id: 'chez-mon-libraire',
    name: 'Chez mon libraire (Auvergne-Rhône-Alpes)',
    country: 'FR',
    // Same engine as Place des libraires (EAN-only URL 301s to the fiche).
    bookUrlTemplate: 'https://www.chez-mon-libraire.fr/livre/{ean13}',
  ),
  BookshopPortal(
    id: 'todostuslibros',
    name: 'Todos tus libros',
    country: 'ES',
    // CEGAL portal. Search redirects to the book page on a hit; unknown
    // ISBN lands on an empty result page.
    bookUrlTemplate: 'https://www.todostuslibros.com/busquedas?keyword={ean13}',
    isCountryDefault: true,
  ),
];

BookshopPortal? bookshopPortalById(String id) {
  for (final portal in bookshopPortalRegistry) {
    if (portal.id == id) return portal;
  }
  return null;
}

/// Default portals for an ISO 3166-1 alpha-2 [country] code,
/// case-insensitive. Empty when no verified portal covers that country yet.
List<BookshopPortal> bookshopPortalsForCountry(String country) {
  final upper = country.toUpperCase();
  return [
    for (final portal in bookshopPortalRegistry)
      if (portal.isCountryDefault && portal.country == upper) portal,
  ];
}

/// Case- and diacritic-insensitive substring search over portal names.
/// An empty [query] returns the whole registry (it is small), so the
/// settings autocomplete can list everything on focus.
List<BookshopPortal> searchBookshopPortals(String query) {
  final needle = _fold(query.trim());
  if (needle.isEmpty) return List.of(bookshopPortalRegistry);
  return [
    for (final portal in bookshopPortalRegistry)
      if (_fold(portal.name).contains(needle)) portal,
  ];
}

/// Targets the book card should offer: the reader's own registry
/// selection (unknown ids skipped) followed by their hand-added entries;
/// the country defaults only when the reader configured nothing at all.
List<BookLinkTarget> bookshopPortalsForDisplay({
  required List<String> selectedIds,
  required String country,
  List<BookLinkTarget> customs = const [],
}) {
  final chosen = <BookLinkTarget>[
    for (final id in selectedIds)
      if (bookshopPortalById(id) case final BookshopPortal portal) portal,
    ...customs,
  ];
  if (chosen.isNotEmpty) return chosen;
  return bookshopPortalsForCountry(country);
}

String _fold(String s) {
  const diacritics = 'àâäáãéèêëíîïóôöõúùûüçñ';
  const plain = 'aaaaaeeeeiiiooooouuuucn';
  final lower = s.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = diacritics.indexOf(char);
    buffer.write(index >= 0 ? plain[index] : char);
  }
  return buffer.toString();
}
