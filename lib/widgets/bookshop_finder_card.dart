import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/bookshop_portals.dart';
import 'book_links_config_sheet.dart';
import 'portal_chip.dart';

/// "Find it at an independent bookshop" card on a wanted book's page.
///
/// Sits below [WishlistAvailabilityCard] on purpose: borrowing from the
/// network stays the primary path, buying is the parallel offer. Pure
/// outbound deep link: the portal locates nearby shops itself from the
/// ISBN, so no reader location ever leaves the app.
///
/// Opens as an in-app browser view (Custom Tab / SFSafariViewController;
/// url_launcher falls back to the external browser on desktop). NOT a raw
/// WebView on purpose: the portal's geolocation prompt would then require
/// the app itself to declare a location permission, and webview_flutter
/// does not cover Windows/Linux.
///
/// The close cross dismisses the card GLOBALLY (all books), via
/// [ThemeProvider.setShowBookshopFinder]; a reader refusing buying
/// suggestions refuses them everywhere, not book by book. Re-enabled
/// from the bookshops section of the settings screen; the librarian and
/// bookseller presets switch it off.
///
/// Renders nothing when dismissed, without a valid ISBN, or without a
/// verified portal for the reader's country (see bookshop_portals.dart).
class BookshopFinderCard extends StatelessWidget {
  final Book book;

  const BookshopFinderCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<ThemeProvider>().showBookshopFinder) {
      return const SizedBox.shrink();
    }
    // No ISBN guard: hand-added title-based templates can still link;
    // registry portals return null without a valid ISBN.
    final isbn = book.isbn ?? '';
    final themeProvider = context.read<ThemeProvider>();
    final entries = <(BookLinkTarget, Uri)>[
      for (final portal in bookshopPortalsForDisplay(
        selectedIds: themeProvider.myBookshopIds,
        country: themeProvider.country,
        customs: themeProvider.myCustomBookshops,
      ))
        if (portal.bookUri(isbn, title: book.title) case final Uri uri)
          (portal, uri),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dismissLabel =
        TranslationService.translate(context, 'bookshop_finder_dismiss');

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'bookshop_finder_title',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, size: 18),
                  tooltip: TranslationService.translate(
                    context,
                    'bookshop_finder_configure',
                  ),
                  onPressed: () => showBookLinksConfigSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: dismissLabel,
                  onPressed: () {
                    final provider = context.read<ThemeProvider>();
                    provider.setShowBookshopFinder(false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          TranslationService.translate(context, 'card_hidden'),
                        ),
                        action: SnackBarAction(
                          label: TranslationService.translate(
                            context,
                            'action_undo',
                          ),
                          onPressed: () =>
                              provider.setShowBookshopFinder(true),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                TranslationService.translate(context, 'bookshop_finder_hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (portal, uri) in entries)
                  PortalChip(
                    icon: Icons.storefront_outlined,
                    label: portal.name,
                    uri: uri,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
