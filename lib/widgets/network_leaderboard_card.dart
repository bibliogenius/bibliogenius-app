import 'package:flutter/material.dart';

import '../models/leaderboard_entry.dart';
import '../services/translation_service.dart';

class NetworkLeaderboardCard extends StatefulWidget {
  final Map<String, List<LeaderboardEntry>> leaderboard;
  final String? lastRefreshed;
  final VoidCallback? onRefresh;

  const NetworkLeaderboardCard({
    super.key,
    required this.leaderboard,
    this.lastRefreshed,
    this.onRefresh,
  });

  @override
  State<NetworkLeaderboardCard> createState() => _NetworkLeaderboardCardState();
}

class _NetworkLeaderboardCardState extends State<NetworkLeaderboardCard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRefreshing = false;

  static const _domains = ['collector', 'reader', 'lender', 'cataloguer'];
  static const _domainIcons = [
    Icons.menu_book,
    Icons.auto_stories,
    Icons.handshake,
    Icons.shelves,
  ];
  static const _domainTitleKeys = [
    'leaderboard_collector',
    'leaderboard_reader',
    'leaderboard_lender',
    'leaderboard_cataloguer',
  ];
  static const _domainDescKeys = [
    'leaderboard_collector_desc',
    'leaderboard_reader_desc',
    'leaderboard_lender_desc',
    'leaderboard_cataloguer_desc',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _domains.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      widget.onRefresh?.call();
    } finally {
      // Allow parent to rebuild this widget with new data;
      // a short delay avoids the spinner disappearing instantly.
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
              : [Colors.white, const Color(0xFFF5F7FA)],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.leaderboard,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                              context, 'leaderboard_title'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (widget.lastRefreshed != null)
                          Text(
                            _formatStaleness(widget.lastRefreshed!),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.onRefresh != null)
                    _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            tooltip: TranslationService.translate(
                                context, 'action_refresh'),
                            onPressed: _handleRefresh,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                ],
              ),
              const SizedBox(height: 16),

              // Tab bar
              TabBar(
                controller: _tabController,
                isScrollable: false,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: List.generate(_domains.length, (i) {
                  return Tab(icon: Icon(_domainIcons[i], size: 20));
                }),
              ),
              const SizedBox(height: 8),

              // Tab content
              SizedBox(
                height: _calculateTabHeight(),
                child: TabBarView(
                  controller: _tabController,
                  children: List.generate(_domains.length, (i) {
                    final domain = _domains[i];
                    final entries = widget.leaderboard[domain] ?? [];
                    if (entries.isEmpty) {
                      return Center(
                        child: Text(
                          TranslationService.translate(
                            context,
                            'leaderboard_empty',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return _buildDomainTab(i, entries);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStaleness(String isoDate) {
    try {
      final syncTime = DateTime.parse(isoDate);
      final age = DateTime.now().difference(syncTime);

      if (age.inMinutes < 1) {
        return TranslationService.translate(context, 'synced_just_now');
      } else if (age.inMinutes < 60) {
        final label =
            TranslationService.translate(context, 'synced_minutes_ago');
        return label.replaceAll('%d', age.inMinutes.toString());
      } else if (age.inHours < 24) {
        final label =
            TranslationService.translate(context, 'synced_hours_ago');
        return label.replaceAll('%d', age.inHours.toString());
      } else {
        final label =
            TranslationService.translate(context, 'synced_days_ago');
        return label.replaceAll('%d', age.inDays.toString());
      }
    } catch (_) {
      return isoDate;
    }
  }

  double _calculateTabHeight() {
    final maxEntries = _domains
        .map((d) => (widget.leaderboard[d] ?? []).length)
        .fold(0, (a, b) => a > b ? a : b);
    // 48px header + 56px per entry + padding, min 100 for empty state
    return (48 + maxEntries.clamp(0, 6) * 56.0 + 8).clamp(100.0, 396.0);
  }

  Widget _buildDomainTab(int domainIndex, List<LeaderboardEntry> entries) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Domain header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                _domainIcons[domainIndex],
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                TranslationService.translate(
                  context,
                  _domainTitleKeys[domainIndex],
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslationService.translate(
                    context,
                    _domainDescKeys[domainIndex],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Ranking list
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length.clamp(0, 6),
            itemBuilder: (context, index) {
              return _buildRankRow(index + 1, entries[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRankRow(int rank, LeaderboardEntry entry) {
    final theme = Theme.of(context);
    final isSelf = entry.isSelf;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelf
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Rank medal or number
          SizedBox(
            width: 32,
            child: _buildRankBadge(rank),
          ),
          const SizedBox(width: 12),
          // Library name
          Expanded(
            child: Text(
              isSelf
                  ? '${entry.libraryName} (${TranslationService.translate(context, 'leaderboard_you')})'
                  : entry.libraryName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelf ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _levelColor(entry.level).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _levelName(entry.level),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _levelColor(entry.level),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Current value
          Text(
            '${entry.current}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank <= 3) {
      final colors = [
        const Color(0xFFFFD700), // Gold
        const Color(0xFFC0C0C0), // Silver
        const Color(0xFFCD7F32), // Bronze
      ];
      return Icon(Icons.emoji_events, color: colors[rank - 1], size: 22);
    }
    return Text(
      '#$rank',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  String _levelName(int level) {
    if (level >= 6) {
      return '${TranslationService.translate(context, 'level_platine')}+';
    }
    final keys = [
      'level_curieux',
      'level_novice',
      'level_apprenti',
      'level_bronze',
      'level_silver',
      'level_gold',
    ];
    return TranslationService.translate(context, keys[level]);
  }

  Color _levelColor(int level) {
    if (level >= 6) return const Color(0xFFE5E4E2); // Platinum
    if (level >= 5) return const Color(0xFFFFD700); // Gold
    if (level >= 4) return const Color(0xFFC0C0C0); // Silver
    if (level >= 3) return const Color(0xFFCD7F32); // Bronze
    if (level >= 2) return const Color(0xFF667eea); // Apprenti
    if (level >= 1) return const Color(0xFF764ba2); // Novice
    return Colors.grey;
  }
}
