import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/operation_log_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../theme/app_design.dart';

class OperationLogScreen extends StatefulWidget {
  const OperationLogScreen({super.key});

  @override
  State<OperationLogScreen> createState() => _OperationLogScreenState();
}

class _OperationLogScreenState extends State<OperationLogScreen> {
  /// Narrowest a stat tile can get and stay legible. Four of them fit above
  /// this, otherwise the strip folds to two columns instead of hiding tiles
  /// behind a horizontal scroll with no affordance.
  static const double _minStatCardWidth = 88.0;

  /// Width a log row needs to keep timestamp, badge, entity, id and controls
  /// on a single line. Scaled with the user's text size at the call site.
  static const double _entryWideWidth = 420.0;

  /// Leading characters of an entity id kept on screen. Enough to tell two
  /// rows apart at a glance, short enough to leave the entity type readable.
  static const int _entityIdDisplayLength = 8;

  late OperationLogProvider _provider;
  final Set<int> _expandedIds = {};
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<OperationLogProvider>();
    _provider.loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _provider.setSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // Explicit: the screen is a destination of the settings branch, so a
        // caller that navigated with `go` (or a deep link) leaves an empty
        // stack and the implied back button never appears. Pop when there is
        // something to pop, otherwise return to where the entry point lives.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: TranslationService.translate(context, 'back'),
          onPressed: () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
            } else {
              router.go('/settings');
            }
          },
        ),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'admin_operation_log_title'),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: TranslationService.translate(
              context,
              _isSearching ? 'cancel' : 'admin_log_search_hint',
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _provider.setSearchQuery(null);
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: Consumer<OperationLogProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: () => provider.loadAll(),
            // Wide windows: cap the body like the other list screens so log
            // rows keep a readable measure instead of stretching edge to edge.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDesign.maxContentWidth,
                ),
                child: CustomScrollView(
                  slivers: [
                    // Stats strip
                    SliverToBoxAdapter(
                      child: _buildStatsStrip(provider, theme),
                    ),
                    // Search bar (toggled)
                    if (_isSearching)
                      SliverToBoxAdapter(child: _buildSearchBar(theme)),
                    // Filter bar
                    SliverToBoxAdapter(
                      child: _buildFilterBar(provider, theme),
                    ),
                    // Entries. hasScrollBody is false so the placeholders grow
                    // past a short landscape viewport instead of overflowing.
                    if (provider.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (provider.entries.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(theme),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildLogEntry(provider.entries[index], theme),
                          childCount: provider.entries.length,
                        ),
                      ),
                    // Pagination
                    if (!provider.isLoading && provider.entries.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildPagination(provider, theme),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsStrip(OperationLogProvider provider, ThemeData theme) {
    final stats = provider.stats;
    final cards = <Widget>[
      _buildStatCard(
        theme,
        TranslationService.translate(context, 'admin_log_stat_total'),
        stats?.total.toString() ?? '-',
        theme.colorScheme.primary,
      ),
      _buildStatCard(
        theme,
        TranslationService.translate(context, 'admin_log_stat_today'),
        stats?.today.toString() ?? '-',
        Colors.blue,
      ),
      _buildStatCard(
        theme,
        TranslationService.translate(context, 'admin_log_stat_pending'),
        stats?.pending.toString() ?? '-',
        Colors.amber.shade700,
      ),
      _buildStatCard(
        theme,
        TranslationService.translate(context, 'admin_log_stat_errors'),
        stats?.failed.toString() ?? '-',
        Colors.red,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      // The tiles share the available width instead of sitting at a fixed 80px:
      // one row of four when it stays legible, two rows of two on a phone.
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final fitsOneRow =
              constraints.maxWidth >= _minStatCardWidth * 4 + gap * 3;
          final perRow = fitsOneRow ? 4 : 2;
          final rows = <Widget>[];

          for (var start = 0; start < cards.length; start += perRow) {
            final end = (start + perRow).clamp(0, cards.length);
            final rowChildren = <Widget>[];
            for (var i = start; i < end; i++) {
              if (i > start) rowChildren.add(const SizedBox(width: gap));
              rowChildren.add(Expanded(child: cards[i]));
            }
            if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rowChildren,
                ),
              ),
            );
          }

          return Column(children: rows);
        },
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A five-digit counter still fits a two-column tile on a small
            // phone rather than being clipped.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: TranslationService.translate(
            context,
            'admin_log_search_hint',
          ),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: TranslationService.translate(
                    context,
                    'admin_log_clear_search',
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _provider.setSearchQuery(null);
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildFilterBar(OperationLogProvider provider, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // Wrap rather than a horizontal scroll: on a phone the chips flow onto a
      // second line instead of hiding off-screen, and they stay reachable at
      // large text sizes.
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildFilterChip(
            tooltip: TranslationService.translate(
              context,
              'tooltip_filter_entity_type',
            ),
            label:
                provider.entityTypeFilter ??
                TranslationService.translate(
                  context,
                  'admin_log_filter_entity',
                ),
            isActive: provider.entityTypeFilter != null,
            options: provider.entityTypes,
            onSelected: (v) => provider.setEntityTypeFilter(v),
          ),
          _buildFilterChip(
            tooltip: TranslationService.translate(
              context,
              'tooltip_filter_operation',
            ),
            label:
                provider.operationFilter ??
                TranslationService.translate(
                  context,
                  'admin_log_filter_operation',
                ),
            isActive: provider.operationFilter != null,
            options: const ['INSERT', 'UPDATE', 'DELETE'],
            onSelected: (v) => provider.setOperationFilter(v),
          ),
          _buildFilterChip(
            tooltip: TranslationService.translate(
              context,
              'tooltip_filter_status',
            ),
            label:
                provider.statusFilter ??
                TranslationService.translate(
                  context,
                  'admin_log_filter_status',
                ),
            isActive: provider.statusFilter != null,
            options: const ['pending', 'applied', 'failed', 'skipped'],
            onSelected: (v) => provider.setStatusFilter(v),
          ),
          if (provider.entityTypeFilter != null ||
              provider.operationFilter != null ||
              provider.statusFilter != null ||
              provider.searchQuery != null)
            TextButton(
              onPressed: () {
                _searchController.clear();
                provider.resetFilters();
              },
              child: Text(
                TranslationService.translate(
                  context,
                  'admin_log_clear_filters',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String tooltip,
    required String label,
    required bool isActive,
    required List<String> options,
    required ValueChanged<String?> onSelected,
  }) {
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<String?>(
        onSelected: onSelected,
        itemBuilder: (context) => [
          if (isActive)
            PopupMenuItem(
              value: null,
              child: Text(
                TranslationService.translate(context, 'filter_all'),
              ),
            ),
          ...options.map((o) => PopupMenuItem(value: o, child: Text(o))),
        ],
        child: Chip(
          // The active filter puts its raw value here, and entity types can be
          // long: keep the chip inside the line rather than past its edge.
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          side: isActive
              ? BorderSide(color: Theme.of(context).colorScheme.primary)
              : null,
        ),
      ),
    );
  }

  /// Short label for the row's entity. Ids have been uuids since the uuid
  /// primary key migration and a whole one never fits a log line, so only the
  /// leading segment is shown; the complete value stays in the expanded
  /// payload. The previous version branched on `entityId == 0` on a String
  /// field, so it never ran and every row rendered a 36-character uuid.
  String _resolveEntityId(frb.FrbOperationLogEntry entry) {
    final id = entry.entityId;
    // Milestones are logged without an entity of their own.
    if (id.isEmpty) return '';
    if (id.length <= _entityIdDisplayLength) return '#$id';
    return '#${id.substring(0, _entityIdDisplayLength)}…';
  }

  Widget _buildLogEntry(frb.FrbOperationLogEntry entry, ThemeData theme) {
    final isExpanded = _expandedIds.contains(entry.id);
    final time = _formatTime(entry.createdAt);

    final entityId = _resolveEntityId(entry);

    return Semantics(
      button: true,
      // The timestamp is the one column a screen reader used to miss, and the
      // compact layout now puts it on a line of its own.
      label:
          '$time, ${entry.operation} ${entry.entityType}'
          '${entityId.isEmpty ? '' : ' $entityId'}, status ${entry.status}',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedIds.remove(entry.id);
              } else {
                _expandedIds.add(entry.id);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The header carries five items. Below the threshold (raised
                // with the user's text size) the timestamp drops to its own
                // line rather than squeezing the entity type off the row.
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final isCompact =
                    constraints.maxWidth < _entryWideWidth * textScale;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEntryHeader(
                      entry,
                      theme,
                      time: time,
                      isExpanded: isExpanded,
                      isCompact: isCompact,
                    ),
                    // Expanded: payload
                    if (isExpanded && entry.payload != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _formatPayload(entry.payload!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                    if (isExpanded && entry.errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Header of a log row: timestamp, operation badge, entity, status and the
  /// expand affordance. One line when there is room, two when there is not.
  Widget _buildEntryHeader(
    frb.FrbOperationLogEntry entry,
    ThemeData theme, {
    required String time,
    required bool isExpanded,
    required bool isCompact,
  }) {
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      fontFamily: 'monospace',
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Flexible: a long entity type ellipsizes instead of overflowing the row.
    final identity = Row(
      children: [
        _operationBadge(entry.operation, theme),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            entry.entityType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Ids are uuids: bound them too, otherwise a single row is wider than
        // any phone.
        Flexible(
          child: Text(
            _resolveEntityId(entry),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    final trailing = <Widget>[
      _statusDot(entry.status, theme),
      const SizedBox(width: 4),
      Tooltip(
        message: isExpanded
            ? TranslationService.translate(context, 'tooltip_collapse_details')
            : TranslationService.translate(context, 'tooltip_expand_details'),
        child: Icon(
          isExpanded ? Icons.expand_less : Icons.expand_more,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];

    if (!isCompact) {
      return Row(
        children: [
          Text(time, style: timeStyle),
          const SizedBox(width: 8),
          Expanded(child: identity),
          ...trailing,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: identity), ...trailing]),
        const SizedBox(height: 2),
        Text(time, style: timeStyle),
      ],
    );
  }

  Widget _operationBadge(String operation, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    Color bg;
    Color fg;
    switch (operation) {
      case 'INSERT':
        bg = isDark ? Colors.green.shade900 : Colors.green.shade50;
        fg = isDark ? Colors.green.shade300 : Colors.green.shade700;
        break;
      case 'UPDATE':
        bg = isDark ? Colors.blue.shade900 : Colors.blue.shade50;
        fg = isDark ? Colors.blue.shade300 : Colors.blue.shade700;
        break;
      case 'DELETE':
        bg = isDark ? Colors.red.shade900 : Colors.red.shade50;
        fg = isDark ? Colors.red.shade300 : Colors.red.shade700;
        break;
      default:
        bg = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
        fg = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        operation,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _statusDot(String status, ThemeData theme) {
    Color color;
    switch (status) {
      case 'pending':
        color = Colors.amber;
        break;
      case 'applied':
        color = Colors.green;
        break;
      case 'failed':
        color = Colors.red;
        break;
      case 'skipped':
        color = Colors.grey;
        break;
      default:
        color = Colors.grey;
    }

    return ExcludeSemantics(
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildPagination(OperationLogProvider provider, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: TranslationService.translate(context, 'tooltip_prev_page'),
            onPressed: provider.page > 0 ? () => provider.previousPage() : null,
          ),
          Text(
            TranslationService.translate(context, 'admin_log_page_info')
                .replaceFirst('%d', '${provider.page + 1}')
                .replaceFirst('%d', '${provider.totalPages}'),
            style: theme.textTheme.bodyMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: TranslationService.translate(context, 'tooltip_next_page'),
            onPressed: provider.page < provider.totalPages - 1
                ? () => provider.nextPage()
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_remove_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'admin_log_empty_title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              TranslationService.translate(context, 'admin_log_empty_subtitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String createdAt) {
    try {
      final dt = DateTime.parse(createdAt);
      final date =
          '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (_) {
      return createdAt;
    }
  }

  String _formatPayload(String raw) {
    try {
      final decoded = Uri.decodeFull(raw);
      return decoded;
    } catch (_) {
      return raw;
    }
  }
}
