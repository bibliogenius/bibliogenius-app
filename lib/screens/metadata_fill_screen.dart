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
import '../theme/app_design.dart';
import '../utils/book_display.dart';
import '../widgets/cached_book_cover.dart';
import '../src/rust/api/frb.dart' as frb;

/// Tone of an empty state: a completed library earns the success colours, a
/// filter that matches nothing stays neutral.
enum _EmptyTone { neutral, success }

class MetadataFillScreen extends StatefulWidget {
  const MetadataFillScreen({super.key});

  @override
  State<MetadataFillScreen> createState() => _MetadataFillScreenState();
}

class _MetadataFillScreenState extends State<MetadataFillScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Minimum tap height for the custom pills (HIG 44pt / Material 48dp).
  static const double _minTapTarget = 44;

  /// Canonical gap-fill field order for filter chips. Title leads: a book
  /// without one is unidentifiable everywhere, including on peers.
  static const _fillFields = [
    'title',
    'summary',
    'publisher',
    'page_count',
    'publication_year',
    'cover_url',
  ];

  /// Candidate lot sizes. The selector offers those smaller than the current
  /// backlog, plus "Tout" (null). Small batches nudge against very long runs.
  static const List<int> _batchCandidates = [10, 20, 30];

  /// Default lot size, preferred when still valid for the current backlog.
  static const int _defaultBatch = 20;

  /// Picked lot size (null = "Tout"). Clamped to the offered set at build/run
  /// time via [_effectiveBatch], so it stays valid as the backlog shrinks.
  int? _batchSize = _defaultBatch;

  /// Lot options for a given backlog: candidates below it, then "Tout".
  List<int?> _offeredBatches(int backlog) => [
    ..._batchCandidates.where((n) => n < backlog),
    null,
  ];

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
      case 'title':
        return _t('field_title');
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
          // "Is there anything to complete" is a property of the library, not
          // of the current slice: reading it off the filtered list would make
          // the tabs and the filter bar vanish under a filter that returns
          // nothing, with no way left to clear it.
          final hasTodo =
              (provider.stats?.incomplete.toInt() ??
                  provider.incomplete.length) >
              0;
          final hasRecent = provider.recent.isNotEmpty;
          final tab = _tabController.index;
          final counts = _missingCounts(provider);
          final filter = provider.filter;
          final scope = provider.scopeField;

          return Center(
            // The app's standard content width: cards stretched across a
            // desktop window leave the covers marooned at the far left.
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDesign.maxContentWidth,
              ),
              child: Column(
                children: [
                  // Fixed header: teaser + action + tabs + filters, kept above
                  // the fold so switching lists never requires scrolling.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDesign.spacingMd,
                      AppDesign.spacingMd,
                      AppDesign.spacingMd,
                      0,
                    ),
                    child: Column(
                      children: [
                        _buildTeaser(provider, scope),
                        const SizedBox(height: AppDesign.spacingMd),
                        _buildActionStrip(
                          provider,
                          scope: scope,
                          noIsbnScope: provider.isNoIsbnFilter,
                        ),
                        if (filter == MetadataFillProvider.coverField) ...[
                          const SizedBox(height: AppDesign.spacingSm),
                          _coversNote(provider),
                        ],
                      ],
                    ),
                  ),
                  if (hasTodo || hasRecent) ...[
                    const SizedBox(height: AppDesign.spacingMd),
                    _buildTabBar(provider),
                    if (tab == 0 && hasTodo)
                      _buildFilterBar(provider, counts, filter),
                  ],
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: provider.loadAll,
                      child: _buildListArea(provider, hasTodo, hasRecent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Missing-field tallies for the filter pills, read from the completeness
  /// stat: it counts the whole library, while `incomplete` is a capped slice of
  /// the *filtered* set — counting that would make every pill report the filter
  /// already applied. No stat yet means no pills yet, rather than wrong ones.
  ({Map<String, int> byField, int noIsbn}) _missingCounts(
    MetadataFillProvider provider,
  ) {
    final stats = provider.stats;
    if (stats == null) return (byField: const {}, noIsbn: 0);
    return (byField: provider.fieldGaps, noIsbn: stats.noIsbn.toInt());
  }

  // ── Teaser (balanced stat card) ───────────────────────────────────────────

  Widget _buildTeaser(MetadataFillProvider provider, String? scope) {
    final theme = Theme.of(context);
    final stats = provider.stats;
    // Under a field filter the card reports that field, not the library: the
    // gap count, the percentage and the bar all switch together, so the number
    // can never contradict the filter the user just tapped.
    final percent = scope == null
        ? provider.completionPercent
        : provider.fieldCompletionPercent(scope);
    final ratio = scope == null
        ? provider.completionRatio
        : provider.fieldCompletionRatio(scope);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDesign.spacingSm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  ),
                  child: Icon(
                    Icons.auto_fix_high,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppDesign.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          _t('completeness_card_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDesign.spacingXs / 2),
                      if (stats != null)
                        Text(
                          scope == null
                              ? _t(
                                  'completeness_empty_fields',
                                  params: {'n': '${provider.emptyFields}'},
                                )
                              : _t(
                                  'completeness_empty_fields_field',
                                  params: {
                                    'n': '${provider.fieldGap(scope)}',
                                    'field': _fieldLabel(scope),
                                  },
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDesign.spacingSm),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppDesign.spacingMd),
            // Visual echo of the percentage read out just above it, so it is
            // kept out of the screen reader's path rather than announced twice.
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDesign.radiusRound),
                child: LinearProgressIndicator(value: ratio, minHeight: 10),
              ),
            ),
            // The filter is what makes those numbers mean "this field" instead
            // of "the library". Show it inside the card that carries them, with
            // its own way out.
            if (provider.filter != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(
                    Icons.filter_alt,
                    size: 18,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  label: Text(_activeFilterLabel(provider)),
                  onDeleted: () => provider.setFilter(null),
                  deleteButtonTooltipMessage: _t('completeness_filter_clear'),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  side: BorderSide.none,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Human label of the active filter, sentinel included.
  String _activeFilterLabel(MetadataFillProvider provider) =>
      provider.isNoIsbnFilter
      ? _t('completeness_no_isbn_chip')
      : _fieldLabel(provider.filter ?? '');

  // ── Action strip (compact, state-dependent) ───────────────────────────────

  Widget _buildActionStrip(
    MetadataFillProvider provider, {
    required String? scope,
    required bool noIsbnScope,
  }) {
    final progress = provider.progress;
    if (provider.isRunning && progress != null) {
      return _runningStrip(provider, progress);
    }
    // The "no ISBN" pill is not a run scope: the fill identifies a book by its
    // ISBN, so these books are the ones it can never process. Say it, rather
    // than leave a start button that would quietly work on other books.
    if (noIsbnScope) return _noIsbnScopeStrip();

    // Scoped backlog when a filter is active (null while the exact count
    // loads), whole backlog otherwise.
    final scopedCount = provider.scopedProcessableCount;
    final backlog = scopedCount ?? provider.processableCount;
    final nothingToDo = scopedCount == 0;
    final Widget action;
    if (provider.isResumable && progress != null) {
      action = _resumeStrip(provider);
    } else if (provider.isCompleted && progress != null) {
      action = _finishedStrip(provider, progress, nothingToDo);
    } else if (nothingToDo) {
      action = _allDoneStrip(scope);
    } else {
      action = _startButton(provider, scope, scopedCount, backlog);
    }

    // Offer the lot selector above whichever non-running action (start / rerun
    // / resume), so the user can size the next lot from any state — not only on
    // the very first run.
    final offered = _offeredBatches(backlog);
    if (nothingToDo || offered.length <= 1) return action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _batchSelector(offered, _effectiveBatch(offered)),
        const SizedBox(height: AppDesign.spacingSm),
        action,
      ],
    );
  }

  Widget _startButton(
    MetadataFillProvider provider,
    String? scope,
    int? scopedCount,
    int backlog,
  ) {
    final theme = Theme.of(context);
    // The lot selector is rendered once, by the action strip above: it belongs
    // to every non-running state, not to the start button.
    final effective = _effectiveBatch(_offeredBatches(backlog));
    final count = effective ?? backlog;
    final String label;
    if (scope == null) {
      label = count > 0
          ? _t('completeness_start_n', params: {'n': '$count'})
          : _t('completeness_start_button');
    } else if (scopedCount == null) {
      // The exact scoped backlog has not landed yet: name the scope rather than
      // announce a count from the wrong slice.
      label = _t(
        'completeness_start_filtered',
        params: {'field': _fieldLabel(scope)},
      );
    } else {
      label = _t(
        'completeness_start_n_filtered',
        params: {'n': '$count', 'field': _fieldLabel(scope)},
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              // A 40dp default button is under the 44pt minimum target.
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: provider.starting ? null : _start,
            icon: provider.starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(label),
          ),
        ),
        // A scoped run picks the books, not the values: whatever is missing on
        // the books it visits gets filled. Spell it out under the button.
        if (scope != null) ...[
          const SizedBox(height: AppDesign.spacingSm),
          Text(
            _t('completeness_scope_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Why a run leaves most covers empty. A missing cover is rarely a failure of
  /// the fill: it usually means no enabled source publishes one for that ISBN,
  /// which the startup sweep already established book by book. Says how many
  /// are in that case rather than offering a general reassurance.
  Widget _coversNote(MetadataFillProvider provider) {
    final theme = Theme.of(context);
    final exhausted = provider.coversSourcesHaveNot ?? 0;
    return _stripContainer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              exhausted > 0
                  ? _t(
                      'completeness_covers_unavailable',
                      params: {'n': '$exhausted'},
                    )
                  : _t('completeness_covers_hint'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown in place of the start button while the "no ISBN" pill is active.
  Widget _noIsbnScopeStrip() {
    final theme = Theme.of(context);
    return _stripContainer(
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _t('completeness_no_isbn_scope'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// One-line reminder of the scope a live or resumable run was started with.
  Widget _scopeLine(String field) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        _t('completeness_scope_running', params: {'field': _fieldLabel(field)}),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
                if (provider.runScopeField != null)
                  _scopeLine(provider.runScopeField!),
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
                        borderRadius: BorderRadius.circular(
                          AppDesign.radiusRound,
                        ),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesign.spacingSm),
                    Text(
                      ratio == null ? '—' : '${(ratio * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
    final theme = Theme.of(context);
    final progress = provider.progress;
    final done = progress?.done ?? 0;
    final total = progress?.total ?? 0;
    // An interrupted run resumes on the scope it was started with: its cursor
    // only means anything against that work-list. When the pills now ask for
    // something else, say which one "Continuer" will honour.
    final runScope = provider.runScopeField;
    final scopeLocked = provider.scopeField != runScope;
    // A lot pauses the run as "interrupted"; show how far the campaign got so
    // the strip reads as "continue", not just "a run was interrupted".
    final label = total > 0
        ? _t(
            'completeness_progress_count',
            params: {'done': '$done', 'total': '$total'},
          )
        : _t('completeness_resume_hint');
    return _stripContainer(
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline, size: 20),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (runScope != null) _scopeLine(runScope),
                Text(label, style: theme.textTheme.bodySmall),
                if (scopeLocked) ...[
                  const SizedBox(height: AppDesign.spacingXs),
                  Text(
                    runScope != null
                        ? _t(
                            'completeness_scope_locked',
                            params: {'field': _fieldLabel(runScope)},
                          )
                        : _t('completeness_scope_locked_all'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: provider.cancel,
            child: Text(_t('completeness_discard_button')),
          ),
          const SizedBox(width: AppDesign.spacingXs),
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
              _t(
                key,
                params: {
                  'filled': '${progress.filled}',
                  'skipped': '${progress.skipped}',
                  'errored': '${progress.errored}',
                },
              ),
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

  /// Nothing left to run. Under a filter this says so *about that filter*:
  /// its books can be there and still be unprocessable (no ISBN), which is not
  /// the same claim as "the library is complete".
  Widget _allDoneStrip(String? scope) {
    final scoped = scope != null;
    return _stripContainer(
      child: Row(
        children: [
          Icon(
            scoped ? Icons.filter_alt_off : Icons.check_circle,
            color: scoped ? null : Colors.green,
          ),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              scoped
                  ? _t(
                      'completeness_scope_all_done',
                      params: {'field': _fieldLabel(scope)},
                    )
                  : _t('completeness_all_done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stripContainer({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingMd - 4,
        vertical: AppDesign.spacingSm + 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
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
          // The exact library-wide count, like the pills below: the list itself
          // is capped, and a tab that says 300 next to a pill saying 412 reads
          // as a bug.
          text: _t(
            'completeness_tab_todo',
            params: {
              'n':
                  '${provider.stats?.incomplete.toInt() ?? provider.incomplete.length}',
            },
          ),
        ),
        Tab(
          text: _t(
            'completeness_tab_recent',
            params: {'n': '${provider.recent.length}'},
          ),
        ),
      ],
    );
  }

  // ── Filter pills (catalog style) ──────────────────────────────────────────

  Widget _buildFilterBar(
    MetadataFillProvider provider,
    ({Map<String, int> byField, int noIsbn}) tallies,
    String? filter,
  ) {
    final counts = tallies.byField;
    final noIsbnCount = tallies.noIsbn;
    final filterFields = _fillFields
        .where((f) => (counts[f] ?? 0) > 0)
        .toList();
    final optionCount = filterFields.length + (noIsbnCount > 0 ? 1 : 0);
    if (optionCount <= 1) return const SizedBox(height: AppDesign.spacingSm);

    final total =
        provider.stats?.incomplete.toInt() ?? provider.incomplete.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        AppDesign.spacingSm,
        AppDesign.spacingMd,
        AppDesign.spacingXs,
      ),
      child: Row(
        children: [
          _filterPill(
            label: _t('completeness_filter_all', params: {'n': '$total'}),
            selected: filter == null,
            onTap: () => provider.setFilter(null),
          ),
          for (final f in filterFields)
            _filterPill(
              label: '${_fieldLabel(f)} (${counts[f]})',
              selected: filter == f,
              onTap: () =>
                  provider.setFilter(filter == f ? null : f),
            ),
          if (noIsbnCount > 0)
            _filterPill(
              label: '${_t('completeness_no_isbn_chip')} ($noIsbnCount)',
              selected: filter == MetadataFillProvider.noIsbnFilter,
              warn: true,
              onTap: () => provider.setFilter(
                filter == MetadataFillProvider.noIsbnFilter
                    ? null
                    : MetadataFillProvider.noIsbnFilter,
              ),
            ),
        ],
      ),
    );
  }

  /// Catalog-style filter pill. Kept a Material/InkWell rather than a Chip to
  /// match the catalog bar, so it carries its own semantics (a bare InkWell is
  /// announced as plain text) and its own 44pt minimum tap height.
  Widget _filterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool warn = false,
  }) {
    final theme = Theme.of(context);
    final active = warn ? theme.colorScheme.error : theme.colorScheme.primary;
    final fg = selected
        ? (warn ? theme.colorScheme.onError : theme.colorScheme.onPrimary)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: AppDesign.spacingSm),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? active : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: _minTapTarget),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesign.spacingMd,
                vertical: AppDesign.spacingSm,
              ),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── List area (responsive grid) ───────────────────────────────────────────

  Widget _buildListArea(
    MetadataFillProvider provider,
    bool hasTodo,
    bool hasRecent,
  ) {
    if (!hasTodo && !hasRecent) {
      // Single scrollable so pull-to-refresh still works on an empty library.
      return _scrollableCentered(
        _emptyState(
          icon: Icons.verified,
          title: _t('completeness_all_done'),
          tone: _EmptyTone.success,
        ),
      );
    }

    final isTodo = _tabController.index == 0;
    final String hint;
    final List<Widget> cards;
    if (isTodo) {
      hint = _t('completeness_todo_hint');
      cards = provider.incomplete
          .map((b) => _buildTodoCard(provider, b))
          .toList();
    } else {
      hint = _t('completeness_recent_hint');
      cards = provider.recent
          .map((b) => _buildRecentCard(provider, b))
          .toList();
    }

    if (cards.isEmpty) {
      // Under a filter the list is a capped slice of the filtered set, so it
      // can legitimately come back empty right after a run finished the last
      // matching books. Say which state the page is in instead of showing a
      // blank area under a filter bar that still announces counts.
      return _scrollableCentered(
        _emptyState(
          icon: isTodo ? Icons.filter_alt_off : Icons.history_toggle_off,
          title: isTodo
              ? _t('completeness_filter_empty')
              : _t('completeness_recent_hint'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const spacing = AppDesign.spacingMd;
        final avail = c.maxWidth - AppDesign.spacingMd * 2;
        // Width breakpoints: 2 columns as soon as a phone portrait allows it.
        final cols = avail >= 1000
            ? 4
            : avail >= 660
            ? 3
            : avail >= 330
            ? 2
            : 1;
        final cellW = cols <= 1 ? avail : (avail - spacing * (cols - 1)) / cols;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppDesign.spacingMd,
            AppDesign.spacingSm,
            AppDesign.spacingMd,
            AppDesign.spacingLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDesign.spacingMd),
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

  /// Keeps pull-to-refresh alive around a non-scrolling state.
  Widget _scrollableCentered(Widget child) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(AppDesign.spacingLg),
    children: [child],
  );

  /// Illustrated empty state: an icon disc over a short line, so an empty area
  /// reads as an answer rather than as a page that failed to load.
  Widget _emptyState({
    required IconData icon,
    required String title,
    _EmptyTone tone = _EmptyTone.neutral,
  }) {
    final theme = Theme.of(context);
    final bg = tone == _EmptyTone.success
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = tone == _EmptyTone.success
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppDesign.spacingMd),
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: ExcludeSemantics(child: Icon(icon, size: 32, color: fg)),
        ),
        const SizedBox(height: AppDesign.spacingMd),
        Text(
          title,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildTodoCard(
    MetadataFillProvider provider,
    frb.FrbIncompleteBookDetail book,
  ) {
    final theme = Theme.of(context);
    final hasIsbn = (book.isbn ?? '').trim().isNotEmpty;
    // A book listed here may be the one missing its very title: resolve it to
    // its ISBN, or to the placeholder, so the row reporting the gap is not
    // itself blank.
    final displayTitle = BookDisplay.titleFor(
      context,
      title: book.title,
      isbn: book.isbn,
    );
    return Semantics(
      button: true,
      label: displayTitle,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          onTap: () => _openBookEditor(book.id),
          child: Padding(
            padding: const EdgeInsets.all(AppDesign.spacingSm + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CompactBookCover(
                      imageUrl: book.coverUrl,
                      size: 44,
                      semanticLabel: displayTitle,
                    ),
                    const SizedBox(width: AppDesign.spacingSm + 2),
                    Expanded(
                      child: Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: AppDesign.spacingSm),
                // Chips span the full card width (not the narrow column beside
                // the cover), so they wrap onto fewer lines and the card stays
                // short.
                Wrap(
                  spacing: AppDesign.spacingXs + 2,
                  runSpacing: AppDesign.spacingXs + 2,
                  children: [
                    if (!hasIsbn)
                      _tag(_t('completeness_no_isbn_chip'), warn: true),
                    ...book.missing.map((f) => _tag(_fieldLabel(f))),
                  ],
                ),
              ],
            ),
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
    final displayTitle = BookDisplay.titleFor(context, title: book.title);
    final batchId = book.fields.isNotEmpty ? book.fields.first.batchId : '';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        onTap: () => _showBookChanges(book.bookId),
        child: Padding(
          padding: const EdgeInsets.all(AppDesign.spacingSm + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CompactBookCover(
                    imageUrl: book.coverUrl,
                    size: 44,
                    semanticLabel: displayTitle,
                  ),
                  const SizedBox(width: AppDesign.spacingSm + 2),
                  Expanded(
                    // The row itself opens the change sheet; the undo button
                    // beside it is a second, separate action, so the title
                    // carries the sheet's semantics rather than the whole card.
                    child: Semantics(
                      button: true,
                      label: displayTitle,
                      child: Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
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
              const SizedBox(height: AppDesign.spacingSm),
              Wrap(
                spacing: AppDesign.spacingXs + 2,
                runSpacing: AppDesign.spacingXs + 2,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingSm,
        vertical: AppDesign.spacingXs / 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        // A filled grey chip on a card surface is nearly invisible; the hairline
        // gives it an edge without adding another colour to the page.
        border: Border.all(
          color: warn || added
              ? Colors.transparent
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (added) ...[
            Icon(Icons.check, size: 12, color: fg),
            const SizedBox(width: AppDesign.spacingXs / 2),
          ],
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
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
                AppDesign.spacingMd,
                0,
                AppDesign.spacingMd,
                AppDesign.spacingMd +
                    MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: book == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDesign.spacingLg,
                      ),
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
                              semanticLabel: BookDisplay.titleFor(
                                context,
                                title: book.title,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      BookDisplay.titleFor(
                                        context,
                                        title: book.title,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _t('completeness_changes_subtitle'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDesign.spacingSm),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: book.fields
                                .map((f) => _buildChangeRow(provider, f))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: AppDesign.spacingSm),
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
                const SizedBox(width: AppDesign.spacingSm),
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
    // Size the lot against the same backlog the button announced. While a
    // scoped count is still loading there is no backlog to clamp against, and
    // clamping against the unscoped one would size the run on another slice:
    // take the user's pick as it stands.
    final backlog = provider.scopedProcessableCount;
    final batch = backlog == null
        ? _batchSize
        : _effectiveBatch(_offeredBatches(backlog));
    final languages = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).userLanguages;
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
