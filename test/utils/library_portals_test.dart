import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/library_portals.dart';

void main() {
  group('parseLibraryResultUrl', () {
    test('substitutes the witness EAN wherever it appears', () {
      final parse = parseLibraryResultUrl(
        'https://opac.example.fr/search/9782070408504?q=9782070408504',
      );
      expect(
        parse.template,
        'https://opac.example.fr/search/{ean13}?q={ean13}',
      );
      expect(parse.error, isNull);
    });

    test('tolerates surrounding whitespace from the clipboard', () {
      final parse = parseLibraryResultUrl(
        '  https://opac.example.fr/?q=9782070408504\n',
      );
      expect(parse.template, 'https://opac.example.fr/?q={ean13}');
    });

    test('rejects a URL with embedded whitespace', () {
      final parse = parseLibraryResultUrl(
        'https://opac.example.fr/?q=9782070408504 malicious',
      );
      expect(parse.error, LibraryTemplateError.notHttps);
    });

    test('rejects plain http', () {
      final parse = parseLibraryResultUrl(
        'http://opac.example.fr/?q=9782070408504',
      );
      expect(parse.error, LibraryTemplateError.notHttps);
    });

    test('turns a title search into a {title} template', () {
      final parse = parseLibraryResultUrl(
        'https://opac.example.fr/recherche?q=le+petit+prince&page=1',
      );
      expect(parse.template, 'https://opac.example.fr/recherche?q={title}&page=1');
    });

    test('recognises percent-encoded and hyphenated title shapes', () {
      expect(
        parseLibraryResultUrl('https://x.fr/?q=Petit%20Prince').template,
        'https://x.fr/?q={title}',
      );
      expect(
        parseLibraryResultUrl('https://x.fr/s/petit-prince').template,
        'https://x.fr/s/{title}',
      );
    });

    test('the witness EAN wins over the title when both appear', () {
      final parse = parseLibraryResultUrl(
        'https://x.fr/?q=9782070408504&t=petit+prince',
      );
      expect(parse.template, 'https://x.fr/?q={ean13}&t=petit+prince');
    });

    test('rejects a URL without the witness EAN', () {
      final parse = parseLibraryResultUrl(
        'https://opac.example.fr/resultats?session=abc123',
      );
      expect(parse.error, LibraryTemplateError.witnessMissing);
    });
  });

  group('LocalLibraryPortal', () {
    const portal = LocalLibraryPortal(
      name: 'Mediatheque test',
      urlTemplate: 'https://opac.example.fr/?q={ean13}',
    );

    test('renders the template with the normalised EAN-13', () {
      expect(
        portal.bookUri('207036822X').toString(),
        'https://opac.example.fr/?q=9782070368228',
      );
    });

    test('invalid ISBN yields no link', () {
      expect(portal.bookUri('not-an-isbn'), isNull);
    });

    const titlePortal = LocalLibraryPortal(
      name: 'Mediatheque titre',
      urlTemplate: 'https://opac.example.fr/recherche?q={title}',
    );

    test('title template substitutes the encoded book title', () {
      expect(
        titlePortal.bookUri('', title: "L'Anomalie 2020").toString(),
        "https://opac.example.fr/recherche?q=L'Anomalie%202020",
      );
    });

    test('title template without a title yields no link', () {
      expect(titlePortal.bookUri('9782070408504', title: '  '), isNull);
    });

    test('fromJson accepts a title-based template', () {
      expect(
        LocalLibraryPortal.fromJson({
          'name': 'x',
          'url_template': 'https://x.fr/?q={title}',
        }),
        isNotNull,
      );
    });

    test('JSON roundtrip', () {
      final decoded = LocalLibraryPortal.fromJson(portal.toJson());
      expect(decoded!.name, portal.name);
      expect(decoded.urlTemplate, portal.urlTemplate);
    });

    test('a non-https template never renders a link', () {
      const evil = LocalLibraryPortal(
        name: 'evil',
        urlTemplate: 'javascript:alert(1)?q={ean13}',
      );
      expect(evil.bookUri('9782070408504'), isNull);
    });

    test('fromJson refuses non-https or control-character templates', () {
      expect(
        LocalLibraryPortal.fromJson({
          'name': 'x',
          'url_template': 'http://x.fr/?q={ean13}',
        }),
        isNull,
      );
      expect(
        LocalLibraryPortal.fromJson({
          'name': 'x',
          'url_template': 'javascript:alert(1)?q={title}',
        }),
        isNull,
      );
      expect(
        LocalLibraryPortal.fromJson({
          'name': 'x',
          'url_template': 'https://x.fr/?q={ean13}\nmalicious',
        }),
        isNull,
      );
    });

    test('fromJson refuses malformed entries', () {
      expect(LocalLibraryPortal.fromJson('junk'), isNull);
      expect(LocalLibraryPortal.fromJson({'name': 'x'}), isNull);
      expect(
        LocalLibraryPortal.fromJson({
          'name': 'x',
          'url_template': 'https://no-placeholder.example',
        }),
        isNull,
      );
    });
  });
}
