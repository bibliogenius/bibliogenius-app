import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbWishlistProvider;
import '../utils/borrow_eligibility.dart';

/// "Available from" card shown on the details page of a wanted book.
///
/// Renders nothing unless the shared Rust join (wishlist_service) returns
/// at least one provider: no dedicated empty state by design, matches are
/// rare (the bottleneck is thematic overlap between libraries, not code).
///
/// Borrow paths: paired peers go through the local backend
/// (requestBookByUrl: E2EE, relay, plaintext fallback, outgoing tracking);
/// followed-but-not-paired libraries go through the hub borrow request.
class WishlistAvailabilityCard extends StatefulWidget {
  final Book book;

  const WishlistAvailabilityCard({super.key, required this.book});

  @override
  State<WishlistAvailabilityCard> createState() =>
      _WishlistAvailabilityCardState();
}

class _WishlistAvailabilityCardState extends State<WishlistAvailabilityCard> {
  List<FrbWishlistProvider> _providers = [];
  BorrowRequestSnapshot _requests = BorrowRequestSnapshot.empty;
  /// ISBNs with a pending hub borrow request, per lender node id.
  final Set<String> _pendingHubNodes = {};
  /// Sources tapped in this session (optimistic disable, both paths).
  final Set<String> _requestedNow = {};

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

    final api = context.read<ApiService>();
    // First load: on failure fall back to the empty snapshot (there is no
    // previous state to preserve; buttons just stay enabled, the backend
    // rejects duplicates with a 409).
    final requests =
        await BorrowRequestSnapshot.load(api) ?? BorrowRequestSnapshot.empty;

    // Pending hub-mediated requests (followed libraries without pairing).
    final pendingHub = <String>{};
    try {
      final hubOutgoing = await ffi.hubDirectoryOutgoingBorrowRequests();
      for (final r in hubOutgoing) {
        if (r.isbn == isbn && r.status == 'pending') {
          pendingHub.add(r.lenderNodeId);
        }
      }
    } catch (_) {
      // Non-blocking: no button gets disabled.
    }

    if (!mounted) return;
    setState(() {
      _providers = providers;
      _requests = requests;
      _pendingHubNodes
        ..clear()
        ..addAll(pendingHub);
    });
  }

  String _sourceKey(FrbWishlistProvider p) =>
      p.peerUrl ?? p.nodeId ?? p.sourceName;

  bool _isPending(FrbWishlistProvider p) {
    if (_requestedNow.contains(_sourceKey(p))) return true;
    final isbn = _isbn;
    if (isbn == null) return false;
    if (p.peerUrl != null) {
      return _requests.pendingIsbns(peerUrl: p.peerUrl).contains(isbn);
    }
    return p.nodeId != null && _pendingHubNodes.contains(p.nodeId);
  }

  bool _canRequest(FrbWishlistProvider p) {
    final isbn = _isbn;
    if (isbn == null) return false;
    return canBorrowBook(
      // The Rust join only returns owned = true cache rows.
      owned: true,
      availableCopies: p.availableCopies,
      hasPendingRequest: _isPending(p),
      isActiveBorrow: p.peerUrl != null &&
          _requests.activeBorrowIsbns(peerUrl: p.peerUrl).contains(isbn),
      isLending: p.peerUrl != null &&
          _requests.lendingIsbns(peerUrl: p.peerUrl).contains(isbn),
    );
  }

  String _stateLabel(BuildContext context, FrbWishlistProvider p) {
    final isbn = _isbn;
    if (_isPending(p)) {
      return TranslationService.translate(context, 'borrow_pending');
    }
    if (p.peerUrl != null && isbn != null) {
      if (_requests.activeBorrowIsbns(peerUrl: p.peerUrl).contains(isbn)) {
        return TranslationService.translate(context, 'borrow_active');
      }
      if (_requests.lendingIsbns(peerUrl: p.peerUrl).contains(isbn)) {
        return TranslationService.translate(context, 'borrow_on_loan');
      }
    }
    return TranslationService.translate(context, 'borrow_unavailable');
  }

  Future<void> _request(FrbWishlistProvider p) async {
    final isbn = _isbn;
    if (isbn == null) return;
    // Optimistic disable against double taps.
    setState(() => _requestedNow.add(_sourceKey(p)));

    var sent = false;
    String? errorKey;
    try {
      if (p.peerUrl != null) {
        final api = context.read<ApiService>();
        final response = await api.requestBookByUrl(
          p.peerUrl!,
          isbn,
          widget.book.title,
        );
        final data = response.data;
        if (response.statusCode == 409) {
          errorKey = 'borrow_on_loan';
        } else if (data is Map && data['status'] == 'rejected') {
          errorKey = 'borrow_request_rejected_no_copy';
        } else {
          sent = true;
        }
      } else if (p.nodeId != null) {
        final hub = context.read<HubDirectoryProvider>();
        sent = await hub.createBorrowRequest(
          p.nodeId!,
          isbn,
          widget.book.title,
        );
      }
    } catch (e) {
      debugPrint('Wishlist borrow request failed: $e');
      errorKey = 'borrow_request_rejected_no_copy';
    }

    if (!mounted) return;
    if (!sent) {
      setState(() => _requestedNow.remove(_sourceKey(p)));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(
            context,
            sent ? 'borrow_request_sent' : (errorKey ?? 'borrow_unavailable'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_providers.isEmpty) return const SizedBox.shrink();
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
            for (final p in _providers) _buildProviderRow(context, p),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderRow(BuildContext context, FrbWishlistProvider p) {
    final theme = Theme.of(context);
    final canRequest = _canRequest(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              p.sourceName,
              style: theme.textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (canRequest)
            Semantics(
              button: true,
              label:
                  '${TranslationService.translate(context, 'borrow')} : ${p.sourceName}',
              child: FilledButton.tonal(
                onPressed: () => _request(p),
                child: Text(TranslationService.translate(context, 'borrow')),
              ),
            )
          else
            Text(
              _stateLabel(context, p),
              // onSurfaceVariant, not outline: this is < 18px text and
              // outline sits below the 4.5:1 WCAG AA ratio in the light
              // theme (rule A2).
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
