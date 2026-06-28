// "Compléter ma bibliothèque" screen (ADR-041).
//
// Presentation only: a completeness teaser, a compact action strip
// (start/running/resume/last-run), catalog-style tabs to switch between the
// "to complete" and "recently completed" lists, catalog-style filter pills, and
// a responsive multi-column grid of book cards. All data decisions (what to
// fill, throttle, undo safety) live in the Rust backend.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/metadata_fill_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../widgets/cached_book_cover.dart';
import '../src/rust/api/frb.dart' as frb;

class MetadataFillScreen extends StatefulWidget {
  const MetadataFillScreen({super.key});

  @override
  State<MetadataFillScreen> createState() => _MetadataFillScreenState();
}

class _MetadataFillScreenState extends State<MetadataFillScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Active "missing field" filter on the to-complete list (null = all).
  String? _missingFilter;

  /// Canonical gap-fill field order for filter chips.
  static const _fillFields = [
    'summary',
    'publisher',
    'page_count',
    'publication_year',
    'cover_url',
  ];

  /// Sentinel filter value for "books without an ISBN" (not a gap-fill field).
  static const _noIsbnFilter = '__no_isbn';

  /// Candidate lot sizes. The selector offers those smaller than the current
  /// backlog, plus "Tout" (null). Small batches nudge against very long runs.
  static const List<int> _batchCandidates = [10, 20, 30];

  /// Default lot size, preferred when still valid for the current backlog.
  static const int _defaultBatch = 20;

  /// Picked lot size (null = "Tout"). Clamped to the offered set at build/run
  /// time via [_effectiveBatch], so it stays valid as the backlog shrinks.
  int? _batchSize = _defaultBatch;

  /// Lot options for a given backlog: candidates below it, then "Tout".
  List<int?> _offeredBatches(int backlog) =>
      [..._batchCandidates.where((n) => n < backlog), null];

  /// The picked size if still offered, else a sensible default (the default lot,
  /// else the largest finite option, else "Tout").
  int? _effectiveBatch(List<int?> offered) {
    if (offered.contains(_batchSize)) return _batchSize;
    final finite = offered.whereType<int>().toList();
    if (finite.contains(_defaultBatch)) return _defaultBatch;
    return finite.isNotEmpty ? finite.last : null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MetadataFillProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _t(String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  String _fieldLabel(String field) {
    switch (field) {
      case 'summary':
        return _t('field_summary');
      case 'publisher':
        return _t('field_publisher');
      case 'page_count':
        return _t('field_page_count');
      case 'publication_year':
        return _t('field_publication_year');
      case 'cover_url':
        return _t('field_cover_url');
      default:
        return field;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('completeness_title'))),
      body: Consumer<MetadataFillProvider>(
        builder: (context, provider, _) {
          final hasTodo = provider.incomplete.isNotEmpty;
          final hasRecent = provider.recent.isNotEmpty;
          final tab = _tabController.index;

          return Column(
            children: [
              // Fixed header: teaser + action + tabs + filters, kept above the
              // fold so switching lists never requires scrolling.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    _buildTeaser(provider),
                    const SizedBox(height: 12),
                    _buildActionStrip(provider),
                  ],
                ),
              ),
              if (hasTodo || hasRecent) ...[
                const SizedBox(height: 12),
                _buildTabBar(provider),
                if (tab == 0 && hasTodo) _buildFilterBar(provider),
              ],
              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.loadAll,
                  child: _buildListArea(provider, hasTodo, hasRecent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Teaser (balanced stat card) ───────────────────────────────────────────

  Widget _buildTeaser(MetadataFillProvider provider) {
    final theme = Theme.of(context);
    final stats = provider.stats;
    final percent = provider.completionPercent;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_fix_high,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          _t('completeness_card_title'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (stats != null)
                        Text(
                          _t('completeness_empty_fields',
                              params: {'n': '${provider.emptyFields}'}),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$percent%',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      _t('completeness_complete'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: provider.completionRatio,
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action strip (compact, state-dependent) ───────────────────────────────

  Widget _buildActionStrip(MetadataFillProvider provider) {
    final progress = provider.progress;
    if (provider.isRunning && progress != null) {
      return _runningStrip(provider, progress);
    }

    final nothingToDo = provider.processableCount == 0;
    final Widget action;
    if (provider.isResumable && progress != null) {
      action = _resumeStrip(provider);
    } else if (provider.isCompleted && progress != null) {
      action = _finishedStrip(provider, progress, nothingToDo);
    } else if (nothingToDo) {
      action = _allDoneStrip();
    } else {
      action = _startButton(provider);
    }

    // Offer the lot selector above whichever non-running action (start / rerun
    // / resume), so the user can size the next lot from any state — not only on
    // the very first run.
    final offered = _offeredBatches(provider.processableCount);
    if (nothingToDo || offered.length <= 1) return action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _batchSelector(offered, _effectiveBatch(offered)),
        const SizedBox(height: 8),
        action,
      ],
    );
  }

  Widget _startButton(MetadataFillProvider provider) {
    final offered = _offeredBatches(provider.processableCount);
    final effective = _effectiveBatch(offered);
    // A real choice exists once at least one finite lot fits under the backlog
    // (offered always ends with the "Tout" null entry).
    final hasChoice = offered.length > 1;
    final count = effective ?? provider.processableCount;
    return Column(
      children: [
        if (hasChoice) ...[
          _batchSelector(offered, effective),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: provider.starting ? null : _start,
            icon: provider.starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(
              count > 0
                  ? _t('completeness_start_n', params: {'n': '$count'})
                  : _t('completeness_start_button'),
            ),
          ),
        ),
      ],
    );
  }

  /// Chips to pick how many books a fresh run processes before pausing.
  Widget _batchSelector(List<int?> offered, int? effective) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(
            _t('completeness_batch_label'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final opt in offered)
          ChoiceChip(
            label: Text(opt?.toString() ?? _t('completeness_batch_all')),
            selected: effective == opt,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _batchSize = opt),
          ),
      ],
    );
  }

  Widget _runningStrip(
    MetadataFillProvider provider,
    frb.FrbFillProgress progress,
  ) {
    final theme = Theme.of(context);
    // Lot-relative progress: the bar fills 0→100% for the current lot, while the
    // teaser card above tracks overall library completeness.
    final lotDone = provider.lotDone;
    final lotTotal = provider.lotTotal;
    final ratio = lotTotal > 0 ? lotDone / lotTotal : null;
    final current = progress.currentTitle ?? '';
    return _stripContainer(
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_t('completeness_progress_count', params: {'done': '$lotDone', 'total': '$lotTotal'})}'
                  '${current.isEmpty ? '' : '  ·  $current'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ratio == null ? '—' : '${(ratio * 100).round()}%',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: _t('completeness_cancel_button'),
            onPressed: provider.cancel,
          ),
        ],
      ),
    );
  }

  Widget _resumeStrip(MetadataFillProvider provider) {
    final progress = provider.progress;
    final done = progress?.done ?? 0;
    final total = progress?.total ?? 0;
    // A lot pauses the run as "interrupted"; show how far the campaign got so
    // the strip reads as "continue", not just "a run was interrupted".
    final label = total > 0
        ? _t('completeness_progress_count',
            params: {'done': '$done', 'total': '$total'})
        : _t('completeness_resume_hint');
    return _stripContainer(
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: provider.cancel,
            child: Text(_t('completeness_discard_button')),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: provider.starting ? null : _start,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(_t('completeness_resume_button')),
          ),
        ],
      ),
    );
  }

  Widget _finishedStrip(
    MetadataFillProvider provider,
    frb.FrbFillProgress progress,
    bool nothingToDo,
  ) {
    final theme = Theme.of(context);
    final key = progress.status == 'cancelled'
        ? 'completeness_last_run_cancelled'
        : 'completeness_last_run_done';
    return _stripContainer(
      child: Row(
        children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _t(key, params: {
                'filled': '${progress.filled}',
                'skipped': '${progress.skipped}',
                'errored': '${progress.errored}',
              }),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (!nothingToDo)
            TextButton.icon(
              onPressed: provider.starting ? null : _start,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_t('completeness_rerun_button')),
            ),
        ],
      ),
    );
  }

  Widget _allDoneStrip() {
    return _stripContainer(
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(_t('completeness_all_done'))),
        ],
      ),
    );
  }

  Widget _stripContainer({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  // ── Tabs (catalog style) ──────────────────────────────────────────────────

  Widget _buildTabBar(MetadataFillProvider provider) {
    final theme = Theme.of(context);
    return TabBar(
      controller: _tabController,
      labelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      indicatorColor: theme.colorScheme.primary,
      indicatorWeight: 3,
      tabs: [
        Tab(
          text: _t('completeness_tab_todo',
              params: {'n': '${provider.incomplete.length}'}),
        ),
        Tab(
          text: _t('completeness_tab_recent',
              params: {'n': '${provider.recent.length}'}),
        ),
      ],
    );
  }

  // ── Filter pills (catalog style) ──────────────────────────────────────────

  Widget _buildFilterBar(MetadataFillProvider provider) {
    final books = provider.incomplete;
    final counts = <String, int>{};
    for (final b in books) {
      for (final f in b.missing) {
        counts[f] = (counts[f] ?? 0) + 1;
      }
    }
    final filterFields =
        _fillFields.where((f) => (counts[f] ?? 0) > 0).toList();
    final noIsbnCount =
        books.where((b) => (b.isbn ?? '').trim().isEmpty).length;
    final optionCount = filterFields.length + (noIsbnCount > 0 ? 1 : 0);
    if (optionCount <= 1) return const SizedBox(height: 8);

    final filter = _validFilter(counts, noIsbnCount);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _filterPill(
            label: _t('completeness_filter_all', params: {'n': '${books.length}'}),
            selected: filter == null,
            onTap: () => setState(() => _missingFilter = null),
          ),
          for (final f in filterFields)
            _filterPill(
              label: '${_fieldLabel(f)} (${counts[f]})',
              selected: filter == f,
              onTap: () =>
                  setState(() => _missingFilter = filter == f ? null : f),
            ),
          if (noIsbnCount > 0)
            _filterPill(
              label: '${_t('completeness_no_isbn_chip')} ($noIsbnCount)',
              selected: filter == _noIsbnFilter,
              warn: true,
              onTap: () => setState(
                () => _missingFilter =
                    filter == _noIsbnFilter ? null : _noIsbnFilter,
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool warn = false,
  }) {
    final theme = Theme.of(context);
    final active = warn ? theme.colorScheme.error : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? active : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? (warn
                          ? theme.colorScheme.onError
                          : theme.colorScheme.onPrimary)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The active filter, reset to null when its slice has emptied.
  String? _validFilter(Map<String, int> counts, int noIsbnCount) {
    final f = _missingFilter;
    if (f == null) return null;
    if (f == _noIsbnFilter) return noIsbnCount > 0 ? f : null;
    return (counts[f] ?? 0) > 0 ? f : null;
  }

  // ── List area (responsive grid) ───────────────────────────────────────────

  Widget _buildListArea(
    MetadataFillProvider provider,
    bool hasTodo,
    bool hasRecent,
  ) {
    if (!hasTodo && !hasRecent) {
      // Single scrollable so pull-to-refresh still works on an empty library.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Text(
              _t('completeness_all_done'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    final isTodo = _tabController.index == 0;
    final String hint;
    final List<Widget> cards;
    if (isTodo) {
      hint = _t('completeness_todo_hint');
      cards = _filteredTodo(provider)
          .map((b) => _buildTodoCard(provider, b))
          .toList();
    } else {
      hint = _t('completeness_recent_hint');
      cards = provider.recent
          .map((b) => _buildRecentCard(provider, b))
          .toList();
    }

    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 12.0;
        final avail = c.maxWidth - 32;
        // Width breakpoints: 2 columns as soon as a phone portrait allows it.
        final cols = avail >= 1000
            ? 4
            : avail >= 660
            ? 3
            : avail >= 330
            ? 2
            : 1;
        final cellW =
            cols <= 1 ? avail : (avail - spacing * (cols - 1)) / cols;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: cards
                    .map((w) => SizedBox(width: cellW, child: w))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  List<frb.FrbIncompleteBookDetail> _filteredTodo(
    MetadataFillProvider provider,
  ) {
    final books = provider.incomplete;
    final counts = <String, int>{};
    for (final b in books) {
      for (final f in b.missing) {
        counts[f] = (counts[f] ?? 0) + 1;
      }
    }
    final noIsbnCount =
        books.where((b) => (b.isbn ?? '').trim().isEmpty).length;
    final filter = _validFilter(counts, noIsbnCount);
    if (filter == null) return books;
    if (filter == _noIsbnFilter) {
      return books.where((b) => (b.isbn ?? '').trim().isEmpty).toList();
    }
    return books.where((b) => b.missing.contains(filter)).toList();
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildTodoCard(
    MetadataFillProvider provider,
    frb.FrbIncompleteBookDetail book,
  ) {
    final theme = Theme.of(context);
    final hasIsbn = (book.isbn ?? '').trim().isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openBookEditor(book.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CompactBookCover(
                    imageUrl: book.coverUrl,
                    size: 44,
                    semanticLabel: book.title,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              // Chips span the full card width (not the narrow column beside the
              // cover), so they wrap onto fewer lines and the card stays short.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (!hasIsbn) _tag(_t('completeness_no_isbn_chip'), warn: true),
                  ...book.missing.map((f) => _tag(_fieldLabel(f))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentCard(
    MetadataFillProvider provider,
    frb.FrbFilledBook book,
  ) {
    final theme = Theme.of(context);
    final batchId = book.fields.isNotEmpty ? book.fields.first.batchId : '';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showBookChanges(book.bookId),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CompactBookCover(
                    imageUrl: book.coverUrl,
                    size: 44,
                    semanticLabel: book.title,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    tooltip: _t('action_undo'),
                    visualDensity: VisualDensity.compact,
                    onPressed: batchId.isEmpty
                        ? null
                        : () => _undoBook(provider, batchId, book.bookId),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: book.fields
                    .map((f) => _tag(_fieldLabel(f.field), added: true))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small field tag. `added` shows a check (recently filled); `warn` flags
  /// the no-ISBN marker.
  Widget _tag(String label, {bool added = false, bool warn = false}) {
    final theme = Theme.of(context);
    final bg = warn
        ? theme.colorScheme.errorContainer
        : added
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = warn
        ? theme.colorScheme.onErrorContainer
        : added
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (added) ...[
            Icon(Icons.check, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }

  // ── Per-book changes sheet ────────────────────────────────────────────────

  void _showBookChanges(String bookId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer<MetadataFillProvider>(
          builder: (context, provider, _) {
            frb.FrbFilledBook? book;
            for (final b in provider.recent) {
              if (b.bookId == bookId) {
                book = b;
                break;
              }
            }
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: book == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(_t('completeness_all_undone')),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CompactBookCover(
                              imageUrl: book.coverUrl,
                              size: 40,
                              semanticLabel: book.title,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      book.title,
                                      style:
                                          Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _t('completeness_changes_subtitle'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: book.fields
                                .map((f) => _buildChangeRow(provider, f))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/books/$bookId');
                          },
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(_t('completeness_open_book')),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildChangeRow(MetadataFillProvider provider, frb.FrbFilledField f) {
    final theme = Theme.of(context);
    final isCover = f.field == 'cover_url';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _fieldLabel(f.field),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo, size: 20),
                tooltip: _t('action_undo'),
                onPressed: () => _undoField(provider, f.journalId),
              ),
            ],
          ),
          if (isCover)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CompactBookCover(imageUrl: f.value, size: 48),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    f.value,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else
            SelectableText(f.value, style: theme.textTheme.bodyMedium),
          const Divider(height: 16),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _start() async {
    final provider = context.read<MetadataFillProvider>();
    final batch = _effectiveBatch(_offeredBatches(provider.processableCount));
    final languages =
        Provider.of<ThemeProvider>(context, listen: false).userLanguages;
    await provider.start(languages, lotLimit: batch);
  }

  Future<void> _openBookEditor(String bookId) async {
    await context.push('/books/$bookId');
    if (!mounted) return;
    await context.read<MetadataFillProvider>().refreshAfterManualEdit();
  }

  Future<void> _undoBook(
    MetadataFillProvider provider,
    String batchId,
    String bookId,
  ) async {
    final reverted = await provider.undoBook(batchId, bookId);
    if (!mounted) return;
    _showSnack(
      reverted > 0
          ? _t('completeness_undo_book_done', params: {'n': '$reverted'})
          : _t('completeness_undo_kept'),
    );
  }

  Future<void> _undoField(MetadataFillProvider provider, int journalId) async {
    final outcome = await provider.undoField(journalId);
    if (!mounted) return;
    final msg = switch (outcome) {
      'reverted' => _t('completeness_undo_field_reverted'),
      'superseded' => _t('completeness_undo_field_superseded'),
      _ => null,
    };
    if (msg != null) _showSnack(msg);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
