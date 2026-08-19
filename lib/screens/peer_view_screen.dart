// "What other libraries see" screen.
//
// Read-only mirror of the catalogue as it leaves this device. The data comes
// from the peer-facing HTTP route, unauthenticated, exactly as another library
// fetches it (see `PeerViewService`); nothing is filtered again here, so the
// preview cannot drift from what is actually published.

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/peer_view_service.dart';
import '../services/translation_service.dart';
import '../widgets/cached_book_cover.dart';

class PeerViewScreen extends StatefulWidget {
  const PeerViewScreen({super.key});

  @override
  State<PeerViewScreen> createState() => _PeerViewScreenState();
}

class _PeerViewScreenState extends State<PeerViewScreen> {
  late Future<PeerViewSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = PeerViewService.fetch();
  }

  void _reload() => setState(() => _snapshot = PeerViewService.fetch());

  String _t(String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('peer_view_title'))),
      body: FutureBuilder<PeerViewSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _buildError();
          }
          return _buildSnapshot(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            Text(_t('peer_view_error'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _reload, child: Text(_t('retry'))),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshot(PeerViewSnapshot snapshot) {
    final books = snapshot.books;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        // +1 for the explanation header, always present so the empty case is
        // still explained rather than looking like a loading failure.
        itemCount: books.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader(books.length);
          return _buildBookRow(snapshot, books[index - 1]);
        },
      ),
    );
  }

  Widget _buildHeader(int visibleCount) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('peer_view_intro'), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t('peer_view_hidden_note'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                // The public directory is a different outbound lane with a
                // narrower payload (`public_catalog_condition` + CatalogEntry,
                // owned books only, four fields). Saying so here is what keeps
                // the directory entry points from over-promising: this list is
                // the upper bound of what leaves, never an understatement.
                //
                // Shown unconditionally, deliberately. Gating it on "the hub is
                // enabled" would hide the bound for a reader arriving from the
                // publish banner with the hub still off, which is precisely the
                // reader deciding whether to expose anything at all.
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.public,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t('peer_view_directory_scope'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            visibleCount == 0
                ? _t('peer_view_empty')
                : _t('peer_view_count', params: {'count': '$visibleCount'}),
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildBookRow(PeerViewSnapshot snapshot, Book book) {
    final theme = Theme.of(context);
    final author = book.author?.trim();
    final copies = book.availableCopies;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedBookCover(
              imageUrl: snapshot.coverUrlFor(book),
              width: 44,
              height: 64,
              borderRadius: BorderRadius.circular(4),
              semanticLabel: author == null || author.isEmpty
                  ? book.title
                  : '${book.title}, $author',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (author != null && author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      author,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.wanted == true || copies != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (book.wanted == true)
                          _chip(
                            _t('availability_wanted'),
                            Icons.favorite_border,
                          ),
                        if (copies != null)
                          _chip(
                            _t(
                              'peer_view_available_copies',
                              params: {'count': '$copies'},
                            ),
                            Icons.inventory_2_outlined,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
