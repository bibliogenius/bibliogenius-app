import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbWishlistProvider;
import '../utils/bookshop_portals.dart';
import '../utils/library_portals.dart';
import 'book_links_config_sheet.dart';
import 'borrow_provider_list.dart';
import 'library_portal_wizard.dart';
import 'portal_chip.dart';

/// "Get hold of this book": the three ways to obtain a book, in one place and
/// in decreasing order of certainty.
///
/// It replaces three stacked cards on the book page whose worst property was
/// silence: each rendered nothing when it had nothing to say, so a reader whose
/// network did not have the book saw a page identical to any other and never
/// learned the paths existed. A sheet always opens, and can say "nobody has it"
/// instead of disappearing.
///
/// The order is the point. The first section is real availability, answered by
/// the peer cache. The two below are searches: the app does not know what those
/// catalogues hold, and the copy says so rather than implying otherwise.
class AcquisitionSheet extends StatefulWidget {
  const AcquisitionSheet({
    super.key,
    required this.book,
    required this.onBorrowed,
    required this.onBought,
    this.onAddToWishlist,
    this.availabilityLoader,
  });

  final Book book;

  /// Record a hand-arranged loan: the contact picker the page already owns.
  final Future<void> Function() onBorrowed;

  /// Record an acquisition: ownership on, and off the wishlist.
  final Future<void> Function() onBought;

  /// Offered only when the book is not wished yet, so the sheet closes the
  /// loop both ways: it is also the door INTO the wishlist, not only out.
  final Future<void> Function()? onAddToWishlist;

  /// Test seam for the availability probe, mirroring
  /// [ExternalSuggestionSheet]: the FFI is never initialized in widget tests.
  final Future<List<FrbWishlistProvider>> Function(String isbn)?
  availabilityLoader;

  static Future<void> show(
    BuildContext context, {
    required Book book,
    required Future<void> Function() onBorrowed,
    required Future<void> Function() onBought,
    Future<void> Function()? onAddToWishlist,
    Future<List<FrbWishlistProvider>> Function(String isbn)? availabilityLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AcquisitionSheet(
        book: book,
        onBorrowed: onBorrowed,
        onBought: onBought,
        onAddToWishlist: onAddToWishlist,
        availabilityLoader: availabilityLoader,
      ),
    );
  }

  @override
  State<AcquisitionSheet> createState() => _AcquisitionSheetState();
}

class _AcquisitionSheetState extends State<AcquisitionSheet> {
  /// Narrowest content width that still seats the two outcome sentences on one
  /// line: about 200 each once the icon and padding are in, plus the gap.
  /// Below it they stack. A phone's sheet is around 350 wide, a desktop one
  /// 600.
  static const double _sideBySideWidth = 420;

  List<FrbWishlistProvider> _providers = [];
  bool _probeDone = false;

  String? get _isbn {
    final isbn = widget.book.isbn;
    return (isbn == null || isbn.isEmpty) ? null : isbn;
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  /// Who in the network holds this ISBN.
  ///
  /// Goes through the arbitrary-ISBN lane rather than the wishlist join: the
  /// latter starts from the local wanting books, so on a book that is not
  /// wished it would answer "nobody" without ever looking.
  Future<void> _loadAvailability() async {
    final isbn = _isbn;
    if (isbn == null) {
      setState(() => _probeDone = true);
      return;
    }
    final loader = widget.availabilityLoader;
    List<FrbWishlistProvider> providers = [];
    if (loader != null) {
      providers = await loader(isbn);
    } else {
      final ffi = FfiService();
      if (ffi.isInitialized) {
        providers = await ffi.getIsbnProviders([isbn]);
      }
    }
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _probeDone = true;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    Navigator.of(context).pop();
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = (String key) => TranslationService.translate(context, key);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      t('acquire_book_title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // One gear for the whole sheet: it opens the shared
                // configuration, which carries the bookshops AND the
                // libraries. Sitting inside one of the two sections, as the
                // cards had it, made it read as that section's own.
                IconButton(
                  key: const Key('acquireConfigureButton'),
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: TranslationService.translate(
                    context,
                    'book_links_configure',
                  ),
                  onPressed: () => showBookLinksConfigSheet(context),
                ),
              ],
            ),
            Text(
              widget.book.title,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            _buildNetworkSection(context),
            _buildLibrarySection(context),
            _buildBookshopSection(context),
            _buildOutcomeSection(context),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          // The capitals are a caption style, not a pronunciation: a screen
          // reader gets the label as written in the catalogue, since some
          // spell out runs of capitals letter by letter.
          semanticsLabel: label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Color(0xFF757575),
          ),
        ),
      ),
    );
  }

  /// Real availability, and the only section that states one.
  Widget _buildNetworkSection(BuildContext context) {
    final isbn = _isbn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          TranslationService.translate(context, 'wishlist_available_from'),
        ),
        if (!_probeDone)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_providers.isEmpty || isbn == null)
          // The card this replaces rendered nothing here, which is why a
          // reader could not tell "nobody has it" from "the feature is gone".
          Text(
            TranslationService.translate(context, 'acquire_nobody_has_it'),
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          BorrowProviderList(
            isbn: isbn,
            bookTitle: widget.book.title,
            providers: _providers,
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Library catalogues the reader connected. A search, not an availability.
  Widget _buildLibrarySection(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    // Two independent switches, one per block, both in the configuration
    // sheet. The library flag governed only the old intro card; now that the
    // card is gone it governs the block, which is what a reader turning off
    // "library suggestions" was asking for in the first place.
    if (!themeProvider.canBorrowBooks || !themeProvider.showLibraryLinks) {
      return const SizedBox.shrink();
    }

    final isbn = widget.book.isbn ?? '';
    final entries = <(LocalLibraryPortal, Uri)>[
      for (final portal in themeProvider.myLibraryPortals)
        if (portal.bookUri(isbn, title: widget.book.title) case final Uri uri)
          (portal, uri),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          TranslationService.translate(context, 'local_library_card_title'),
        ),
        if (entries.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                TranslationService.translate(context, 'settings_libraries_add'),
              ),
              onPressed: () => LibraryPortalWizard.show(context),
            ),
          )
        else
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBookshopSection(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    if (!themeProvider.showBookshopFinder) return const SizedBox.shrink();

    final isbn = widget.book.isbn ?? '';
    final entries = <(BookLinkTarget, Uri)>[
      for (final portal in bookshopPortalsForDisplay(
        selectedIds: themeProvider.myBookshopIds,
        country: themeProvider.country,
        customs: themeProvider.myCustomBookshops,
      ))
        if (portal.bookUri(isbn, title: widget.book.title) case final Uri uri)
          (portal, uri),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          TranslationService.translate(context, 'bookshop_finder_title'),
        ),
        Text(
          TranslationService.translate(context, 'bookshop_finder_hint'),
          style: Theme.of(context).textTheme.bodySmall,
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
        const SizedBox(height: 24),
      ],
    );
  }

  /// One outcome control: icon, then the sentence, left-aligned.
  ///
  /// The caller sizes it, so the same widget serves both branches of the
  /// layout above.
  Widget _outcomeButton(
    BuildContext context, {
    required Key buttonKey,
    required IconData icon,
    required String labelKey,
    required VoidCallback onPressed,
  }) {
    // Tonal, not outlined: a border alone read as dull next to the tinted
    // Contact button above. The sheet's ladder is then plain fill for the one
    // action that sends something (Borrow), tinted for everything the reader
    // does on their own side, and plain text for the lightest offer.
    return FilledButton.tonalIcon(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          TranslationService.translate(context, labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  /// Closing the loop, which no surface offered before: leaving for a
  /// catalogue and coming back meant reopening the status picker by hand.
  Widget _buildOutcomeSection(BuildContext context) {
    final addToWishlist = widget.onAddToWishlist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          TranslationService.translate(context, 'acquire_once_obtained'),
        ),
        // Side by side where there is room, stacked where there is not. These
        // labels are sentences ("Je l'ai emprunté"), and half of a phone's
        // sheet leaves them about 160pt once the icon is in: cramped, and
        // worse in German or Bulgarian. A desktop sheet is 640 wide, so the
        // pair sits on one line there, which is what it should do.
        LayoutBuilder(
          builder: (context, constraints) {
            final borrowed = _outcomeButton(
              context,
              buttonKey: const Key('acquireBorrowedButton'),
              icon: Icons.arrow_downward,
              labelKey: 'acquire_i_borrowed_it',
              onPressed: () => _run(widget.onBorrowed),
            );
            final bought = _outcomeButton(
              context,
              buttonKey: const Key('acquireBoughtButton'),
              icon: Icons.shopping_bag_outlined,
              labelKey: 'acquire_i_bought_it',
              onPressed: () => _run(widget.onBought),
            );

            if (constraints.maxWidth < _sideBySideWidth) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: borrowed),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: bought),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: borrowed),
                const SizedBox(width: 10),
                Expanded(child: bought),
              ],
            );
          },
        ),
        if (addToWishlist != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('acquireAddToWishlistButton'),
              onPressed: () => _run(addToWishlist),
              icon: const Icon(Icons.favorite_border, size: 18),
              label: Text(
                TranslationService.translate(
                  context,
                  'acquire_add_to_wishlist',
                ),
              ),
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ),
        ],
      ],
    );
  }
}
