import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hub_directory.dart';
import '../providers/hub_directory_provider.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbBook, FrbCatalogEntry;
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../utils/app_constants.dart';
import '../widgets/book_spine.dart';
import '../widgets/genie_app_bar.dart';

/// Displays a library's public catalog (list of ISBNs) fetched from the hub.
///
/// Only reachable for libraries the user actively follows (status = active).
/// Libraries with [requiresApproval] = true have encrypted catalogs on the hub;
/// the Rust layer handles decryption transparently via the shared follow key.
class LibraryCatalogScreen extends StatefulWidget {
  final String nodeId;

  const LibraryCatalogScreen({super.key, required this.nodeId});

  @override
  State<LibraryCatalogScreen> createState() => _LibraryCatalogScreenState();
}

class _LibraryCatalogScreenState extends State<LibraryCatalogScreen> {
  final FfiService _ffi = FfiService();

  HubProfile? _profile;
  List<FrbCatalogEntry> _entries = [];
  bool _loading = true;
  String? _error;
  final Map<String, Map<String, String?>?> _lookupCache = {};
  Set<String> _localIsbns = {};
  String? _decryptedContact;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  List<FrbCatalogEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries.where((e) {
      return e.title.toLowerCase().contains(q) ||
          (e.author?.toLowerCase().contains(q) ?? false) ||
          e.isbn.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Only show loading spinner on first load (no cached data yet)
    final isFirstLoad = _entries.isEmpty;
    if (isFirstLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final profileFrb = await _ffi.hubDirectoryGetProfile(widget.nodeId);
      final entries = await _ffi.hubDirectoryGetCatalog(widget.nodeId);
      final localBooks = await _ffi.getBooks();

      if (!mounted) return;
      setState(() {
        _profile =
            profileFrb != null ? HubProfile.fromFrb(profileFrb) : null;
        // Sort: new entries first, then alphabetical by title
        _entries = entries..sort((a, b) {
          final aNew = _isEntryNew(a);
          final bNew = _isEntryNew(b);
          if (aNew != bNew) return aNew ? -1 : 1;
          return a.title.compareTo(b.title);
        });
        _localIsbns = localBooks
            .where((b) => b.isbn != null && b.isbn!.isNotEmpty)
            .map((b) => b.isbn!)
            .toSet();
      });
      // Decrypt contact info if available on the follow relationship
      _decryptContact();
    } catch (e) {
      if (!mounted) return;
      // Only show error if we have no cached data to display
      if (_entries.isEmpty) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decryptContact() async {
    final provider = context.read<HubDirectoryProvider>();
    final follow = provider.followFor(widget.nodeId);
    debugPrint('[CONTACT-READ] followFor(${widget.nodeId.substring(0, 8)}...): '
        '${follow != null ? "found id=${follow.id} status=${follow.status}" : "NOT FOUND"}');
    if (follow != null) {
      debugPrint('[CONTACT-READ] encryptedContact: ${follow.encryptedContact != null ? "${follow.encryptedContact!.length} chars" : "null"}');
    }
    final blob = follow?.encryptedContact;
    if (blob == null || blob.isEmpty) {
      debugPrint('[CONTACT-READ] no encrypted contact blob, returning');
      return;
    }

    final plaintext = await provider.openContact(blob);
    debugPrint('[CONTACT-READ] decrypted: ${plaintext != null ? "OK (${plaintext.length} chars)" : "FAILED"}');
    if (mounted && plaintext != null) {
      setState(() => _decryptedContact = plaintext);
    }
  }

  bool _isEntryNew(FrbCatalogEntry entry) {
    final firstSeen = entry.firstSeenAt;
    if (firstSeen == null) return false;
    final parsed = DateTime.tryParse(firstSeen);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < AppConstants.newBadgeDays;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final title = _profile?.displayName ??
        TranslationService.translate(context, 'directory_catalog_title');

    return Scaffold(
      appBar: GenieAppBar(title: title),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
        ),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(
                  TranslationService.translate(context, 'action_retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check follow status - catalog only visible to active followers
    final provider = context.watch<HubDirectoryProvider>();
    final followStatus = provider.followStatusFor(widget.nodeId);

    if (followStatus == 'pending') {
      return _PendingApprovalState(nodeId: widget.nodeId);
    }

    if (followStatus == null) {
      return _NotFollowingState(
        nodeId: widget.nodeId,
        requiresApproval: _profile?.requiresApproval ?? false,
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_books_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                  context,
                  'directory_catalog_empty',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_profile != null)
          _ProfileHeader(
            profile: _profile!,
            decryptedContact: _decryptedContact,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: TranslationService.translate(
                  context, 'directory_catalog_search'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: TranslationService.translate(
                          context, 'action_clear'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              '${filtered.length} ${TranslationService.translate(context, 'directory_catalog_isbn_count')}',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 0,
                runSpacing: 20,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: filtered.map((entry) {
                  final seed = entry.isbn.hashCode;
                  final isNew = _isEntryNew(entry);
                  return Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: () => _showBookDetail(entry),
                      child: BookSpine(
                        title: entry.title.isNotEmpty
                            ? entry.title
                            : entry.isbn,
                        subtitle: entry.author,
                        colorSeed: seed,
                        height: 220 + (seed.abs() % 4) * 12.0,
                        width: 60 + (seed.abs() % 3) * 6.0,
                        showNewBand: isNew,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
  void _showBookDetail(FrbCatalogEntry entry) {
    final lang = Localizations.localeOf(context).languageCode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _BookDetailSheet(
        entry: entry,
        lookupCache: _lookupCache,
        localIsbns: _localIsbns,
        ffi: _ffi,
        lang: lang,
        onAdded: (isbn) => setState(() => _localIsbns.add(isbn)),
        lenderNodeId: widget.nodeId,
        allowBorrowing: false, // Hub borrowing disabled (coming soon)
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Book detail bottom sheet (enrichment via ISBN lookup)
// ---------------------------------------------------------------------------

class _BookDetailSheet extends StatefulWidget {
  final FrbCatalogEntry entry;
  final Map<String, Map<String, String?>?> lookupCache;
  final Set<String> localIsbns;
  final FfiService ffi;
  final String lang;
  final ValueChanged<String> onAdded;
  final String lenderNodeId;
  final bool allowBorrowing;

  const _BookDetailSheet({
    required this.entry,
    required this.lookupCache,
    required this.localIsbns,
    required this.ffi,
    required this.lang,
    required this.onAdded,
    required this.lenderNodeId,
    required this.allowBorrowing,
  });

  @override
  State<_BookDetailSheet> createState() => _BookDetailSheetState();
}

class _BookDetailSheetState extends State<_BookDetailSheet> {
  Map<String, String?>? _meta;
  bool _loading = true;
  bool _adding = false;
  bool _borrowing = false;

  @override
  void initState() {
    super.initState();
    if (widget.lookupCache.containsKey(widget.entry.isbn)) {
      _meta = widget.lookupCache[widget.entry.isbn];
      _loading = false;
    } else {
      _loadMetadata();
    }
  }

  Future<void> _loadMetadata() async {
    final result = await widget.ffi.lookupBookMetadata(
      widget.entry.isbn,
      lang: widget.lang,
    );
    widget.lookupCache[widget.entry.isbn] = result;
    if (mounted) {
      setState(() {
        _meta = result;
        _loading = false;
      });
    }
  }

  Future<void> _addToLibrary() async {
    setState(() => _adding = true);
    try {
      final metaTitle = _meta?['title'];
      final metaAuthor = _meta?['author'];
      final yearStr = _meta?['publication_year'];

      final title = (metaTitle != null && metaTitle.isNotEmpty)
          ? metaTitle
          : (widget.entry.title.isNotEmpty
              ? widget.entry.title
              : widget.entry.isbn);
      final author = (metaAuthor != null && metaAuthor.isNotEmpty)
          ? metaAuthor
          : widget.entry.author;

      await widget.ffi.createBook(FrbBook(
        title: title,
        author: author,
        isbn: widget.entry.isbn,
        summary: _meta?['summary'],
        publisher: _meta?['publisher'],
        publicationYear: yearStr != null ? int.tryParse(yearStr) : null,
        coverUrl: _meta?['cover_url'],
        owned: true,
      ));

      widget.onAdded(widget.entry.isbn);

      if (mounted) {
        final successMsg =
            TranslationService.translate(context, 'catalog_added_success');
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _requestBorrow() async {
    setState(() => _borrowing = true);
    try {
      final provider = context.read<HubDirectoryProvider>();
      await provider.createBorrowRequest(
        widget.lenderNodeId,
        widget.entry.isbn,
        _meta?['title'] ?? widget.entry.title,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'borrow_request_sent'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_sending_request')}: $e',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _borrowing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = widget.localIsbns.contains(widget.entry.isbn);
    final coverUrl = _meta?['cover_url'];
    final summary = _meta?['summary'];
    final publisher = _meta?['publisher'];
    final year = _meta?['publication_year'];
    final title = _meta?['title'] ??
        (widget.entry.title.isNotEmpty ? widget.entry.title : null);
    final author = _meta?['author'] ?? widget.entry.author;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Cover + info row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover area
                  SizedBox(
                    width: 120,
                    height: 180,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : coverUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Semantics(
                                  image: true,
                                  label: title != null && author != null
                                      ? '$title, $author'
                                      : title ?? widget.entry.isbn,
                                  child: CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                    errorWidget: (_, _, _) =>
                                        _buildPlaceholderCover(context),
                                  ),
                                ),
                              )
                            : _buildPlaceholderCover(context),
                  ),
                  const SizedBox(width: 16),
                  // Info column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        if (author != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            author,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (publisher != null || year != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            [publisher, year]
                                .whereType<String>()
                                .join(' - '),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'ISBN: ${widget.entry.isbn}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                fontFamily: 'monospace',
                                color: Colors.grey[500],
                              ),
                        ),
                        if (_loading) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  TranslationService.translate(
                                    context,
                                    'catalog_loading_details',
                                  ),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // Summary
              if (!_loading &&
                  summary != null &&
                  summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  summary,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              // "Details not available" message
              if (!_loading && _meta == null) ...[
                const SizedBox(height: 12),
                Text(
                  TranslationService.translate(
                    context,
                    'catalog_details_unavailable',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
              ],
              // Action button
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: isLocal
                    ? FilledButton.tonal(
                        onPressed: null,
                        child: Text(
                          TranslationService.translate(
                            context,
                            'catalog_already_in_library',
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _adding ? null : _addToLibrary,
                        icon: _adding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(
                          TranslationService.translate(
                            context,
                            'catalog_add_to_library',
                          ),
                        ),
                      ),
              ),
              // Borrow button (hub-mediated, ADR-018)
              if (!isLocal && widget.allowBorrowing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _borrowing ? null : _requestBorrow,
                      icon: _borrowing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'request_to_borrow',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(Icons.menu_book, size: 40, color: Colors.grey[400]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header strip
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final HubProfile profile;
  final String? decryptedContact;

  const _ProfileHeader({
    required this.profile,
    this.decryptedContact,
  });

  bool get _hasContactSection =>
      (profile.website != null && profile.website!.isNotEmpty) ||
      (decryptedContact != null && decryptedContact!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onContainer = cs.onPrimaryContainer;
    final onContainerMuted = onContainer.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Identity row --
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary,
                child: Text(
                  profile.displayName.isNotEmpty
                      ? profile.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: onContainer,
                          ),
                    ),
                    if (profile.locationCountry != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          profile.locationCountry!,
                          style: TextStyle(
                            fontSize: 12,
                            color: onContainerMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${profile.bookCount}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: onContainer,
                          ),
                    ),
                    Text(
                      TranslationService.translate(
                          context, 'directory_books'),
                      style: TextStyle(
                        fontSize: 11,
                        color: onContainerMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // -- Contact section --
          if (_hasContactSection) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                color: onContainer.withValues(alpha: 0.15),
              ),
            ),
            if (profile.website != null &&
                profile.website!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _WebsiteLink(
                  url: profile.website!,
                  color: onContainerMuted,
                ),
              ),
            if (decryptedContact != null &&
                decryptedContact!.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.lock_outlined,
                        size: 14, color: onContainerMuted),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      decryptedContact!,
                      style: TextStyle(
                        fontSize: 13,
                        color: onContainer,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Website link (validated, clickable)
// ---------------------------------------------------------------------------

class _WebsiteLink extends StatelessWidget {
  final String url;
  final Color color;

  const _WebsiteLink({required this.url, required this.color});

  /// Normalizes and validates the URL. Returns a safe https/http URI or null.
  static Uri? _safeUri(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Auto-prepend https if missing scheme
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    // Only allow http/https schemes
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // Must have a host with a dot (basic domain validation)
    if (!uri.host.contains('.')) return null;
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    final uri = _safeUri(url);
    if (uri == null) return const SizedBox.shrink();

    final display = uri.toString();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: Row(
        children: [
          Icon(Icons.language, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              display,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// States when catalog is not yet accessible
// ---------------------------------------------------------------------------

class _PendingApprovalState extends StatelessWidget {
  final String nodeId;

  const _PendingApprovalState({required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 64, color: Colors.orange[400]),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                context,
                'directory_catalog_pending',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFollowingState extends StatelessWidget {
  final String nodeId;
  final bool requiresApproval;

  const _NotFollowingState({
    required this.nodeId,
    required this.requiresApproval,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HubDirectoryProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                context,
                'directory_catalog_not_following',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => provider.follow(nodeId),
              icon: const Icon(Icons.add),
              label: Text(
                requiresApproval
                    ? TranslationService.translate(
                        context,
                        'directory_request',
                      )
                    : TranslationService.translate(
                        context,
                        'directory_follow',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
