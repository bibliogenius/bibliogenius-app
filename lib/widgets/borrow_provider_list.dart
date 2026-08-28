import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact_card.dart';
import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbWishlistProvider;
import '../utils/borrow_eligibility.dart';
import 'contact_actions_sheet.dart';

/// Per-provider borrow rows: who holds a book, with the request action.
///
/// Single home of the borrow-request branching, shared by the wishlist
/// availability card (book details) and the external suggestion sheet.
/// Paired peers go through the local backend (requestBookByUrl: E2EE,
/// relay, plaintext fallback, outgoing tracking); followed-but-not-paired
/// libraries go through the hub borrow request (ADR-018).
///
/// The parent loads and filters the providers; this widget only needs the
/// ISBN and title because neither request path requires a local book row
/// (the P2P handler creates it with the borrowed copy once the lender
/// confirms).
class BorrowProviderList extends StatefulWidget {
  const BorrowProviderList({
    super.key,
    required this.isbn,
    required this.bookTitle,
    required this.providers,
  });

  final String isbn;
  final String bookTitle;
  final List<FrbWishlistProvider> providers;

  @override
  State<BorrowProviderList> createState() => _BorrowProviderListState();
}

class _BorrowProviderListState extends State<BorrowProviderList> {
  BorrowRequestSnapshot _requests = BorrowRequestSnapshot.empty;

  /// Actionable contact cards by node id (ADR-067): decrypted from the
  /// follow blob, so only accepted libraries that shared one appear.
  final Map<String, ContactCard> _contactCards = {};

  /// Lender node ids with a pending hub borrow request for this ISBN.
  final Set<String> _pendingHubNodes = {};

  /// Sources tapped in this session (optimistic disable, both paths).
  final Set<String> _requestedNow = {};

  @override
  void initState() {
    super.initState();
    _loadRequestState();
    _loadContactCards();
  }

  Future<void> _loadContactCards() async {
    final hub = context.read<HubDirectoryProvider>();
    if (!hub.isHubEnabled) return;
    final nodeIds = <String>{
      for (final p in widget.providers)
        if (p.nodeId != null && p.nodeId!.isNotEmpty) p.nodeId!,
    };
    for (final nodeId in nodeIds) {
      final blob = hub.followFor(nodeId)?.encryptedContact;
      if (blob == null || blob.isEmpty) continue;
      try {
        final plaintext = await hub.openContact(blob);
        if (plaintext == null) continue;
        final card = ContactCard.decode(plaintext);
        if (!card.isActionable) continue;
        if (!mounted) return;
        setState(() => _contactCards[nodeId] = card);
      } catch (_) {
        // A card that cannot be opened simply offers no Contact button.
      }
    }
  }

  Future<void> _loadRequestState() async {
    final api = context.read<ApiService>();
    // On failure fall back to the empty snapshot (there is no previous
    // state to preserve; buttons just stay enabled, the backend rejects
    // duplicates with a 409).
    final requests =
        await BorrowRequestSnapshot.load(api) ?? BorrowRequestSnapshot.empty;

    // Pending hub-mediated requests (followed libraries without pairing).
    final pendingHub = <String>{};
    try {
      final ffi = FfiService();
      if (ffi.isInitialized) {
        final hubOutgoing = await ffi.hubDirectoryOutgoingBorrowRequests();
        for (final r in hubOutgoing) {
          if (r.isbn == widget.isbn && r.status == 'pending') {
            pendingHub.add(r.lenderNodeId);
          }
        }
      }
    } catch (_) {
      // Non-blocking: no button gets disabled.
    }

    if (!mounted) return;
    setState(() {
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
    if (p.peerUrl != null) {
      return _requests.pendingIsbns(peerUrl: p.peerUrl).contains(widget.isbn);
    }
    return p.nodeId != null && _pendingHubNodes.contains(p.nodeId);
  }

  bool _canRequest(FrbWishlistProvider p) {
    return canBorrowBook(
      // The Rust join only returns owned = true cache rows.
      owned: true,
      availableCopies: p.availableCopies,
      hasPendingRequest: _isPending(p),
      isActiveBorrow: p.peerUrl != null &&
          _requests.activeBorrowIsbns(peerUrl: p.peerUrl).contains(widget.isbn),
      isLending: p.peerUrl != null &&
          _requests.lendingIsbns(peerUrl: p.peerUrl).contains(widget.isbn),
    );
  }

  String _stateLabel(BuildContext context, FrbWishlistProvider p) {
    if (_isPending(p)) {
      return TranslationService.translate(context, 'borrow_pending');
    }
    if (p.peerUrl != null) {
      if (_requests
          .activeBorrowIsbns(peerUrl: p.peerUrl)
          .contains(widget.isbn)) {
        return TranslationService.translate(context, 'borrow_active');
      }
      if (_requests.lendingIsbns(peerUrl: p.peerUrl).contains(widget.isbn)) {
        return TranslationService.translate(context, 'borrow_on_loan');
      }
    }
    return TranslationService.translate(context, 'borrow_unavailable');
  }

  Future<void> _request(FrbWishlistProvider p) async {
    // Optimistic disable against double taps.
    setState(() => _requestedNow.add(_sourceKey(p)));

    var sent = false;
    String? errorKey;
    try {
      if (p.peerUrl != null) {
        final api = context.read<ApiService>();
        final response = await api.requestBookByUrl(
          p.peerUrl!,
          widget.isbn,
          widget.bookTitle,
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
          widget.isbn,
          widget.bookTitle,
        );
      }
    } catch (e) {
      debugPrint('Borrow request failed: $e');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in widget.providers) _buildProviderRow(context, p),
      ],
    );
  }

  Widget _buildProviderRow(BuildContext context, FrbWishlistProvider p) {
    final theme = Theme.of(context);
    final canRequest = _canRequest(p);
    final contactCard = p.nodeId == null ? null : _contactCards[p.nodeId];

    final name = Text(
      p.sourceName,
      style: theme.textTheme.bodyLarge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final actions = <Widget>[
      // Contact stays available even when borrowing is not (pending,
      // on loan...): arranging things by message is exactly what the
      // reader wants then.
      if (contactCard != null) ...[
        Semantics(
          button: true,
          label:
              '${TranslationService.translate(context, 'contact_cta')} : ${p.sourceName}',
          child: OutlinedButton(
            onPressed: () => showContactActionsSheet(
              context,
              card: contactCard,
              bookTitle: widget.bookTitle,
              // A paired peer: the loan can go both ways.
              reciprocal: p.peerUrl != null,
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: Text(TranslationService.translate(context, 'contact_cta')),
          ),
        ),
        const SizedBox(width: 8),
      ],
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
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // With BOTH buttons on a phone-width card the name gets
          // squeezed to an ellipsis; give the actions their own line
          // there. Single-action rows keep the one-line layout.
          final wrap = contactCard != null && constraints.maxWidth < 380;
          if (!wrap) {
            return Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: 8),
                ...actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          );
        },
      ),
    );
  }
}
