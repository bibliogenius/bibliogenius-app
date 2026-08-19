import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/indie_bookshop_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // loadSettings reaches flutter_secure_storage through AuthService when the
    // 'username' pref is absent; mock both plugin layers.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Book wanted({String? isbn}) => Book(
    id: '1',
    title: 'Yvain ou Le chevalier au lion',
    isbn: isbn,
    readingStatus: 'wanting',
  );

  Widget harness(
    ThemeProvider provider,
    Book book, {
    Future<bool> Function(Uri)? launcher,
  }) {
    return MaterialApp(
      home: ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: Scaffold(
          body: IndieBookshopLink(book: book, launcher: launcher),
        ),
      ),
    );
  }

  Future<ThemeProvider> providerFor(String country) async {
    final provider = ThemeProvider();
    await provider.loadSettings();
    await provider.setCountry(country);
    return provider;
  }

  group('IndieBookshopLink.productUrl', () {
    // The ISBN becomes a URL path segment. Anything that is not a plain 10 or
    // 13 character ISBN must never be interpolated into it.
    test('builds the product URL from a clean 13 character ISBN', () {
      expect(
        IndieBookshopLink.productUrl('9782070793693').toString(),
        'https://www.librairiesindependantes.com/product/9782070793693/',
      );
    });

    test('strips hyphens and spaces before building the URL', () {
      expect(
        IndieBookshopLink.productUrl('978-2-07-079369-3').toString(),
        'https://www.librairiesindependantes.com/product/9782070793693/',
      );
    });

    // The site only understands EAN-13: sending it a 10 character ISBN answers
    // with a 77 byte error, measured against the live site on 2026-08-19.
    test('converts a 10 character ISBN to EAN-13, X check digit included', () {
      expect(
        IndieBookshopLink.productUrl('207030238X').toString(),
        'https://www.librairiesindependantes.com/product/9782070302383/',
      );
    });

    test('converts the ISBN-10 entries the rentree lists actually carry', () {
      const expected = {
        '2290315699': '9782290315699', // Tristan et Iseut, Librio
        '2070302385': '9782070302383', // Les Fourberies de Scapin, Folioplus
        '2070513297':
            '9782070513291', // Vendredi ou la vie sauvage, Folio Junior
        '2266104330': '9782266104333', // La riviere a l'envers, Pocket jeunesse
      };
      expected.forEach((isbn10, ean13) {
        expect(
          IndieBookshopLink.productUrl(isbn10).toString(),
          'https://www.librairiesindependantes.com/product/$ean13/',
          reason: '$isbn10 must reach the site as $ean13',
        );
      });
    });

    test('leaves a 13 character ISBN untouched', () {
      expect(
        IndieBookshopLink.productUrl('9782070793693').toString(),
        'https://www.librairiesindependantes.com/product/9782070793693/',
      );
    });

    // A lowercase check digit is a legitimate and common form in imported
    // data. Without case normalisation the filter drops it, the string falls
    // to 9 characters and the link vanishes with no signal at all.
    test('accepts a 10 character ISBN ending in a lowercase x', () {
      expect(
        IndieBookshopLink.productUrl('207030238x').toString(),
        'https://www.librairiesindependantes.com/product/9782070302383/',
      );
    });

    test('refuses a null, empty or wrong-length ISBN', () {
      expect(IndieBookshopLink.productUrl(null), isNull);
      expect(IndieBookshopLink.productUrl(''), isNull);
      expect(IndieBookshopLink.productUrl('12345'), isNull);
      expect(IndieBookshopLink.productUrl('97820707936931234'), isNull);
    });

    test('refuses an ISBN carrying path or scheme tricks', () {
      // The regex drops everything but digits and X, so these collapse to
      // something too short rather than escaping the path segment.
      expect(IndieBookshopLink.productUrl('../../etc/passwd'), isNull);
      expect(IndieBookshopLink.productUrl('https://evil.example/'), isNull);
    });
  });

  group('IndieBookshopLink rendering', () {
    testWidgets('renders the link for a reader in France', (tester) async {
      final provider = await providerFor('FR');
      await tester.pumpWidget(harness(provider, wanted(isbn: '9782070793693')));
      await tester.pump();

      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    // The site indexes French bookshops only. Showing it elsewhere is the same
    // false invitation the French-only category label avoids: it advertises
    // something the reader cannot use.
    testWidgets('renders nothing outside France', (tester) async {
      for (final country in ['ES', 'DE', 'BE', 'CH']) {
        final provider = await providerFor(country);
        await tester.pumpWidget(
          harness(provider, wanted(isbn: '9782070793693')),
        );
        await tester.pump();

        expect(
          find.byType(OutlinedButton),
          findsNothing,
          reason: 'country=$country must not see a French-only bookshop link',
        );
      }
    });

    testWidgets('renders nothing when the book has no usable ISBN', (
      tester,
    ) async {
      final provider = await providerFor('FR');
      for (final isbn in [null, '', 'n/a']) {
        await tester.pumpWidget(harness(provider, wanted(isbn: isbn)));
        await tester.pump();

        expect(
          find.byType(OutlinedButton),
          findsNothing,
          reason: 'isbn=$isbn cannot build a well-formed product URL',
        );
      }
    });

    testWidgets('opens the product URL for the book, not a search page', (
      tester,
    ) async {
      final provider = await providerFor('FR');
      final opened = <Uri>[];

      await tester.pumpWidget(
        harness(
          provider,
          wanted(isbn: '978-2-07-079369-3'),
          launcher: (u) async {
            opened.add(u);
            return true;
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(
        opened.single.toString(),
        'https://www.librairiesindependantes.com/product/9782070793693/',
      );
    });
  });
}
