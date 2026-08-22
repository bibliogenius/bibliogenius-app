import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbWishlistProvider;
import 'borrow_provider_list.dart';

/// "Available from" card shown on the details page of a wanted book.
///
/// Renders nothing unless the shared Rust join (wishlist_service) returns
/// at least one provider: no dedicated empty state by design, matches are
/// rare (the bottleneck is thematic overlap between libraries, not code).
///
/// The per-provider rows and both borrow paths (paired peer via
/// requestBookByUrl, followed library via the hub) live in the shared
/// [BorrowProviderList], also used by the external suggestion sheet.
class WishlistAvailabilityCard extends StatefulWidget {
  final Book book;

  const WishlistAvailabilityCard({super.key, required this.book});

  @override
  State<WishlistAvailabilityCard> createState() =>
      _WishlistAvailabilityCardState();
}

class _WishlistAvailabilityCardState extends State<WishlistAvailabilityCard> {
  List<FrbWishlistProvider> _providers = [];

  String? get _isbn {
    final isbn = widget.book.isbn;
    return (isbn == null || isbn.isEmpty) ? null : isbn;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isbn = _isbn;
    // The Rust join only matches wanting, non-private books; this guard
    // just avoids a pointless FFI round-trip for every other book.
    if (isbn == null || widget.book.readingStatus != 'wanting') return;
    final ffi = FfiService();
    if (!ffi.isInitialized) return;

    final providers = await ffi.getWishlistProviders(isbn: isbn);
    if (!mounted || providers.isEmpty) return;
    setState(() => _providers = providers);
  }

  @override
  Widget build(BuildContext context) {
    final isbn = _isbn;
    if (_providers.isEmpty || isbn == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(Icons.people_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'wishlist_available_from',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            BorrowProviderList(
              isbn: isbn,
              bookTitle: widget.book.title,
              providers: _providers,
            ),
          ],
        ),
      ),
    );
  }
}
