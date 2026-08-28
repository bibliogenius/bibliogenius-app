import 'isbn_validator.dart';
import 'bookshop_portals.dart';

/// Witness book for the library-connection wizard: the user searches it
/// by ISBN OR by title on their library's site, and the pasted result URL
/// is turned into a template by substituting whichever was found (the
/// ISBN wins when both appear: it is the more precise key). Chosen for
/// being held by virtually every French-speaking public library; the
/// title needle is diacritic-free on purpose so a plain lowercase
/// contains() finds it.
const String libraryWitnessIsbn = '9782070408504';
const String libraryWitnessTitle = 'Le Petit Prince';
const String libraryWitnessNeedle = 'petit prince';

/// A reader-configured link target: their local public library's online
/// catalogue (OPAC), or a bookshop added by hand. Unlike [BookshopPortal] entries these are user
/// content, so templates are https-only by construction (wizard gate).
class LocalLibraryPortal implements BookLinkTarget {
  @override
  final String name;

  /// URL template with a literal `{ean13}` placeholder.
  final String urlTemplate;

  const LocalLibraryPortal({required this.name, required this.urlTemplate});

  /// Deep link into the catalogue, or null when the template's
  /// placeholders cannot all be filled: `{ean13}` needs a valid ISBN,
  /// `{title}` a non-empty title (title search reaches ANY edition the
  /// library holds, where an exact-ISBN search would miss).
  @override
  Uri? bookUri(String isbn, {String title = ''}) {
    var url = urlTemplate;
    if (url.contains('{ean13}')) {
      final ean13 = IsbnValidator.toIsbn13(isbn);
      if (ean13 == null) return null;
      url = url.replaceAll('{ean13}', ean13);
    }
    if (url.contains('{title}')) {
      final trimmed = title.trim();
      if (trimmed.isEmpty) return null;
      url = url.replaceAll('{title}', Uri.encodeComponent(trimmed));
    }
    // Re-checked at render on purpose: the https gate must hold even for
    // a template that reached storage without going through the wizard
    // (tampered backup, hand-edited prefs).
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    return uri;
  }

  Map<String, dynamic> toJson() => {'name': name, 'url_template': urlTemplate};

  /// Defensive decode: null on any malformed entry so one bad row never
  /// takes the whole stored list down.
  static LocalLibraryPortal? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = json['name'];
    final template = json['url_template'];
    if (name is! String || name.trim().isEmpty) return null;
    if (template is! String ||
        !(template.contains('{ean13}') || template.contains('{title}'))) {
      return null;
    }
    if (!isSafeHttpsTemplate(template)) return null;
    return LocalLibraryPortal(name: name, urlTemplate: template);
  }
}

/// The https-and-well-formed gate every user-provided template must
/// pass, both when the wizard builds it and again when one is decoded
/// from storage: https scheme, no whitespace or control characters.
bool isSafeHttpsTemplate(String template) {
  if (RegExp(r'[\x00-\x20]').hasMatch(template)) return false;
  final uri = Uri.tryParse(template);
  return uri != null && uri.scheme == 'https';
}

enum LibraryTemplateError { notHttps, witnessMissing }

/// Outcome of parsing the URL pasted at the wizard's last step: either a
/// reusable [template] or the [error] to explain.
class LibraryTemplateParse {
  final String? template;
  final LibraryTemplateError? error;

  const LibraryTemplateParse.ok(String this.template) : error = null;
  const LibraryTemplateParse.failed(LibraryTemplateError this.error)
      : template = null;
}

/// URL-encoded shapes of the witness title in a query string or slug:
/// "petit prince" with an optional leading "le", the words separated by
/// spaces, `+`, `%20`, hyphens or underscores.
final RegExp _witnessTitlePattern = RegExp(
  r'(?:le(?:%20|\+|[-_ ])+)?petit(?:%20|\+|[-_ ])+prince',
  caseSensitive: false,
);

/// Turns the result-page URL the user pasted into a template: every
/// occurrence of the witness EAN becomes `{ean13}`, or, when the user
/// searched by title instead, every URL-encoded shape of the witness
/// title becomes `{title}`. Rejects non-https URLs (user content ends up
/// in outbound links) and URLs carrying neither witness (OPACs that post
/// the query or render client-side cannot be linked this way).
LibraryTemplateParse parseLibraryResultUrl(String pasted) {
  final trimmed = pasted.trim();
  if (!isSafeHttpsTemplate(trimmed)) {
    return const LibraryTemplateParse.failed(LibraryTemplateError.notHttps);
  }
  if (trimmed.contains(libraryWitnessIsbn)) {
    return LibraryTemplateParse.ok(
      trimmed.replaceAll(libraryWitnessIsbn, '{ean13}'),
    );
  }
  if (_witnessTitlePattern.hasMatch(trimmed)) {
    return LibraryTemplateParse.ok(
      trimmed.replaceAll(_witnessTitlePattern, '{title}'),
    );
  }
  return const LibraryTemplateParse.failed(
    LibraryTemplateError.witnessMissing,
  );
}
