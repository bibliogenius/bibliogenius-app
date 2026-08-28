import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/city_repository.dart';
import '../services/translation_service.dart';
import '../utils/library_portals.dart';
import 'book_links_config_sheet.dart';
import 'portal_chip.dart';
import 'library_portal_wizard.dart';

/// "At your library" card on a wanted book's page: deep links into the
/// local public library catalogues the reader connected via the wizard.
/// Sits between the borrow card and the bookshop card: borrowing from a
/// library outranks buying.
///
/// Before any catalogue is connected it renders a dismissible intro
/// state instead of nothing: a configurable feature no card ever hints
/// at is never discovered. The intro carries the wizard CTA and, when
/// the reader's city is known (ADR-035 picker), an outbound
/// OpenStreetMap link listing the libraries around that city; it is
/// hidden for profiles that do not borrow (librarian/bookseller
/// presets, via canBorrowBooks).
class LocalLibraryCard extends StatelessWidget {
  final Book book;

  const LocalLibraryCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final portals = themeProvider.myLibraryPortals;
    if (portals.isEmpty) {
      if (!themeProvider.showLibraryIntro || !themeProvider.canBorrowBooks) {
        return const SizedBox.shrink();
      }
      return const _LibraryIntroCard();
    }
    // No ISBN guard: a title-based catalogue template can link a book
    // that has no ISBN at all; each target decides for itself.
    final isbn = book.isbn ?? '';
    final entries = <(LocalLibraryPortal, Uri)>[
      for (final portal in portals)
        if (portal.bookUri(isbn, title: book.title) case final Uri uri)
          (portal, uri),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_library_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'local_library_card_title',
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
                    'local_library_configure',
                  ),
                  onPressed: () => showBookLinksConfigSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (portal, uri) in entries)
                  PortalChip(
                    icon: Icons.local_library_outlined,
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

class _LibraryIntroCard extends StatefulWidget {
  const _LibraryIntroCard();

  @override
  State<_LibraryIntroCard> createState() => _LibraryIntroCardState();
}

class _LibraryIntroCardState extends State<_LibraryIntroCard> {
  Future<CityRecord?>? _cityLookup;

  @override
  void initState() {
    super.initState();
    final hub = context.read<HubDirectoryProvider>();
    final cityId = hub.localCityId;
    final country = hub.localCityCountry;
    if (cityId != null && country != null && country.isNotEmpty) {
      _cityLookup = CityRepository.shared().lookupById(
        cityId,
        country: country,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String t(String key) => TranslationService.translate(context, key);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_library_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      t('local_library_card_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: t('bookshop_finder_dismiss'),
                  onPressed: () =>
                      context.read<ThemeProvider>().setShowLibraryIntro(false),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                t('library_intro_text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // One primary act (connect), one quieter side door (the map):
            // matching weights made the card read as two equal links.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t('settings_libraries_add')),
                    onPressed: () => LibraryPortalWizard.show(context),
                  ),
                  if (_cityLookup != null)
                    FutureBuilder<CityRecord?>(
                      future: _cityLookup,
                      builder: (context, snapshot) {
                        final city = snapshot.data?.name;
                        if (city == null) return const SizedBox.shrink();
                        final query = Uri.encodeComponent(
                          '${t('library_intro_map_term')} $city',
                        );
                        return TextButton.icon(
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: Text(
                            TranslationService.translate(
                              context,
                              'library_intro_map_link',
                              params: {'city': city},
                            ),
                          ),
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/search?query=$query',
                            ),
                            mode: LaunchMode.inAppBrowserView,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
