import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/operation_log_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;

class OperationLogScreen extends StatefulWidget {
  const OperationLogScreen({super.key});

  @override
  State<OperationLogScreen> createState() => _OperationLogScreenState();
}

class _OperationLogScreenState extends State<OperationLogScreen> {
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
            child: CustomScrollView(
              slivers: [
                // Stats strip
                SliverToBoxAdapter(child: _buildStatsStrip(provider, theme)),
                // Search bar (toggled)
                if (_isSearching)
                  SliverToBoxAdapter(child: _buildSearchBar(theme)),
                // Filter bar
                SliverToBoxAdapter(child: _buildFilterBar(provider, theme)),
                // Entries
                if (provider.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (provider.entries.isEmpty)
                  SliverFillRemaining(child: _buildEmptyState(theme))
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
                  SliverToBoxAdapter(child: _buildPagination(provider, theme)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsStrip(OperationLogProvider provider, ThemeData theme) {
    final stats = provider.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard(
              theme,
              TranslationService.translate(context, 'admin_log_stat_total'),
              stats?.total.toString() ?? '-',
              theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              theme,
              TranslationService.translate(context, 'admin_log_stat_today'),
              stats?.today.toString() ?? '-',
              Colors.blue,
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              theme,
              TranslationService.translate(context, 'admin_log_stat_pending'),
              stats?.pending.toString() ?? '-',
              Colors.amber.shade700,
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              theme,
              TranslationService.translate(context, 'admin_log_stat_errors'),
              stats?.failed.toString() ?? '-',
              Colors.red,
            ),
          ],
        ),
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
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
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
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
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
          if (isActive) const PopupMenuItem(value: null, child: Text('All')),
          ...options.map((o) => PopupMenuItem(value: o, child: Text(o))),
        ],
        child: Chip(
          label: Text(label),
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

  String _resolveEntityId(frb.FrbOperationLogEntry entry) {
    if (entry.entityId == 0 && entry.payload != null) {
      try {
        final map = jsonDecode(entry.payload!) as Map<String, dynamic>;
        final strId = map['_str_id'] as String?;
        if (strId != null && strId.length >= 8) {
          return strId.substring(0, 8);
        }
      } catch (_) {}
    }
    return '#${entry.entityId}';
  }

  Widget _buildLogEntry(frb.FrbOperationLogEntry entry, ThemeData theme) {
    final isExpanded = _expandedIds.contains(entry.id);
    final time = _formatTime(entry.createdAt);

    return Semantics(
      button: true,
      label:
          '${entry.operation} ${entry.entityType} ${_resolveEntityId(entry)}, status ${entry.status}',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: time, operation badge, entity type, id
                Row(
                  children: [
                    Text(
                      time,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _operationBadge(entry.operation, theme),
                    const SizedBox(width: 8),
                    Text(
                      entry.entityType,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _resolveEntityId(entry),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    _statusDot(entry.status, theme),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: isExpanded
                          ? TranslationService.translate(
                              context,
                              'tooltip_collapse_details',
                            )
                          : TranslationService.translate(
                              context,
                              'tooltip_expand_details',
                            ),
                      child: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
            ),
          ),
        ),
      ),
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
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            TranslationService.translate(context, 'admin_log_empty_subtitle'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
