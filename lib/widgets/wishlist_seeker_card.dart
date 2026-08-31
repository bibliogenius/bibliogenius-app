import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbWishlistSeeker;

/// "Wanted by" card shown on the details page of an OWNED book: the peers
/// and followed libraries whose wishlist contains it (inverse of
/// the acquisition sheet). Renders nothing when the Rust inverse join
/// returns no seeker.
///
/// UX principle (non-negotiable): lending stays a free, unilateral act.
/// The lend button is the only action; when the relation is mutual (the
/// seeker also owns a book from MY wishlist), that surfaces as a discreet
/// one-line hint under the row, never as a coupled "exchange" action, a
/// counter, or any reciprocity framing.
class WishlistSeekerCard extends StatefulWidget {
  final Book book;

  const WishlistSeekerCard({super.key, required this.book});

  @override
  State<WishlistSeekerCard> createState() => _WishlistSeekerCardState();
}

class _WishlistSeekerCardState extends State<WishlistSeekerCard> {
  List<FrbWishlistSeeker> _seekers = [];

  /// Sources offered a loan in this session (optimistic disable).
  final Set<String> _offeredNow = {};

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
    // The Rust join only matches wanted = true cache rows; this guard just
    // avoids a pointless FFI round-trip for books nobody could have wished.
    if (isbn == null || !widget.book.owned) return;
    final ffi = FfiService();
    if (!ffi.isInitialized) return;

    final seekers = await ffi.getWishlistSeekers(isbn);
    if (!mounted || seekers.isEmpty) return;
    setState(() => _seekers = seekers);
  }

  String _sourceKey(FrbWishlistSeeker s) =>
      s.peerUrl ?? s.nodeId ?? s.sourceName;

  /// Only paired peers can be offered a loan: the offer endpoint needs a
  /// real peer id, and directory-only followers have none (peerId == 0).
  bool _canOffer(FrbWishlistSeeker s) =>
      s.peerId != 0 && !_offeredNow.contains(_sourceKey(s));

  Future<void> _offer(FrbWishlistSeeker s) async {
    // Optimistic disable against double taps; re-enabled on failure.
    setState(() => _offeredNow.add(_sourceKey(s)));

    var sent = false;
    var pendingNotification = false;
    // 409 means "no available copy" specifically; anything else that
    // prevents the offer (network, backend error) gets the generic
    // lending-error message instead of a misleading copy-count claim.
    String errorKey = 'error_lending_book';
    try {
      final api = context.read<ApiService>();
      final response = await api.offerLoanToPeer(
        s.peerId,
        bookId: widget.book.id,
        isbn: _isbn,
      );
      if (response.statusCode == 409) {
        errorKey = 'no_available_copies';
      } else {
        sent = true;
        pendingNotification =
            response.data is! Map || response.data['notification_sent'] != true;
      }
    } catch (e) {
      debugPrint('Wishlist lend offer failed: $e');
    }

    if (!mounted) return;
    if (!sent) {
      setState(() => _offeredNow.remove(_sourceKey(s)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.translate(context, errorKey)),
        ),
      );
      return;
    }
    final suffix = pendingNotification
        ? ' (${TranslationService.translate(context, 'loan_notification_pending')})'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${TranslationService.translate(context, 'book_lent_to')} ${s.sourceName}$suffix',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_seekers.isEmpty) return const SizedBox.shrink();
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
                  Icon(
                    Icons.favorite_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'wishlist_wanted_by',
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
            for (final s in _seekers) _buildSeekerRow(context, s),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekerRow(BuildContext context, FrbWishlistSeeker s) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.sourceName,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_canOffer(s))
                Semantics(
                  button: true,
                  label:
                      '${TranslationService.translate(context, 'wishlist_lend_action')} : ${s.sourceName}',
                  child: FilledButton.tonal(
                    onPressed: () => _offer(s),
                    child: Text(
                      TranslationService.translate(
                        context,
                        'wishlist_lend_action',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Mutual-wish hint: informational only, visually secondary, no
          // action attached (borrowing goes through the usual wishlist
          // card on the wanted book's own page).
          if (s.mutualWishTitles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                TranslationService.translate(
                  context,
                  'wishlist_mutual_hint',
                  params: {
                    'title': _mutualTitleLabel(s.mutualWishTitles),
                    'name': s.sourceName,
                  },
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// First mutual title, with a "(+N)" tail when the seeker could fulfil
  /// several of my wishes. Numbers stay locale-neutral on purpose.
  String _mutualTitleLabel(List<String> titles) {
    if (titles.length == 1) return titles.first;
    return '${titles.first} (+${titles.length - 1})';
  }
}
