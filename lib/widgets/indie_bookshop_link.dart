import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';

/// "Order from an independent bookshop" link for a book the reader wants but
/// does not have yet.
///
/// Sits directly below [WishlistAvailabilityCard] on the book details screen,
/// and that order is deliberate: borrowing from someone you already know comes
/// first, buying second.
///
/// The link points at librairiesindependantes.com, which resolves a book by
/// ISBN and then geolocates the reader to redirect them to one of its
/// affiliated regional bookshop portals. We pass nothing but the ISBN: the
/// site does its own "near me" resolution, so the app never has to know or
/// send a position.
///
/// Two deliberate design decisions:
///
/// 1. **Country-gated, not language-gated.** The site only covers French
///    bookshops, so what matters is where the reader can walk into a shop, not
///    which language they read in. A French speaker in Spain gets nothing
///    useful from it; a German speaker living in France does. [ThemeProvider]
///    already stores `country` as a local preference.
///
/// 2. **Not gated on the book actually being available there.** The URL
///    answers HTTP 200 for any ISBN, including malformed ones, and only the
///    response body reveals whether a result was found. Checking would cost
///    one remote request per book, on a partner's site, generating no traffic
///    for them, which is a very different posture from a plain hyperlink.
///    Worst case the reader lands on a page saying the book is not stocked,
///    which is ordinary web behaviour rather than a bug.
///
/// **Known coverage, measured 2026-08-19: 14 of the 27 ISBNs in the two
/// rentree lists resolve on the site.** The cause is ours, not the network's:
/// those lists deliberately point at the widely held older printing, because
/// that is what the owned/total badge compares against, and a bookshop indexes
/// what it can still sell. The two features pull in opposite directions.
///
/// The lever, when someone picks this up, is `alt_editions` rather than more
/// link types: the field already exists and today only carries language
/// variants, so one entry could hold the ISBN you own for the badge and the
/// ISBN in print for this link. That changes the meaning of a field 81 lists
/// use, so it needs its own decision. Publisher links were evaluated and
/// rejected: a per-publisher URL registry is the shape ADR-038 already parked
/// on hold, and a publisher page informs rather than sells.
class IndieBookshopLink extends StatelessWidget {
  final Book book;

  /// Overridable for tests so they never open a real browser.
  final Future<bool> Function(Uri url)? launcher;

  const IndieBookshopLink({super.key, required this.book, this.launcher});

  /// Country whose readers this link is useful to. The site indexes French
  /// bookshops only.
  static const String supportedCountry = 'FR';

  /// Digits and X only, the form the backend stores and the form the site
  /// expects in its path segment.
  ///
  /// Case is normalised BEFORE filtering, the way [IsbnValidator.clean] does:
  /// an ISBN-10 whose check digit is a lowercase `x` is a legitimate and common
  /// form in imported data, and dropping it would silently shorten the string
  /// to nine characters and make the link disappear with no signal.
  ///
  /// The filter stays stricter than [IsbnValidator]'s, which only removes
  /// spaces and hyphens: this value becomes a URL path segment, so everything
  /// that is not a digit or an X has to go.
  static String cleanIsbn(String isbn) =>
      isbn.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');

  /// The EAN-13 form of [clean], which is the only one the site understands.
  ///
  /// Measured against the live site on 2026-08-19: a 10 character ISBN answers
  /// with a 77 byte error, not even the site's own "not found" page, so the
  /// link was simply broken for every entry carrying an older ISBN-10. The
  /// conversion is mechanical: keep the nine significant digits, prefix 978,
  /// recompute the check digit. The ISBN-10's own check digit, `X` included,
  /// is discarded by construction.
  ///
  /// Total by design: anything that is not a plain 10 digit core comes back
  /// unchanged rather than throwing, and the caller's length guard still
  /// decides whether a URL is built at all.
  static String _toEan13(String clean) {
    if (clean.length != 10) return clean;
    final core = '978${clean.substring(0, 9)}';
    if (!RegExp(r'^\d{12}$').hasMatch(core)) return clean;
    var sum = 0;
    for (var i = 0; i < core.length; i++) {
      sum += int.parse(core[i]) * (i.isEven ? 1 : 3);
    }
    return '$core${(10 - (sum % 10)) % 10}';
  }

  /// The public product URL, or null when [isbn] cannot make a well-formed one.
  /// Guards the path segment: an ISBN reaches a URL here, so anything that is
  /// not a plain 10 or 13 character ISBN must not be interpolated.
  static Uri? productUrl(String? isbn) {
    if (isbn == null) return null;
    final clean = cleanIsbn(isbn);
    if (clean.length != 10 && clean.length != 13) return null;
    final ean = _toEan13(clean);
    return Uri.parse('https://www.librairiesindependantes.com/product/$ean/');
  }

  @override
  Widget build(BuildContext context) {
    final country = context.watch<ThemeProvider>().country.toUpperCase();
    if (country != supportedCountry) return const SizedBox.shrink();

    final url = productUrl(book.isbn);
    if (url == null) return const SizedBox.shrink();

    final label = TranslationService.translate(context, 'bookshop_order_indie');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _open(context, url),
          icon: const Icon(Icons.storefront_outlined, size: 18),
          // A bare Text is correct here, do not wrap it in Flexible: the
          // `.icon` constructor already puts the label in one, and a second
          // makes competing ParentDataWidgets throw at build time. The label
          // therefore wraps on its own at large OS text scales, which is what
          // WCAG 1.4.4 asks for.
          label: Text(label),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = TranslationService.translate(
      context,
      'bookshop_open_failed',
    );
    final launch =
        launcher ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    bool ok;
    try {
      ok = await launch(url);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
