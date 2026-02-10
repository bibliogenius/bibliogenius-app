import 'package:flutter/material.dart';

import '../models/leaderboard_entry.dart';
import '../services/translation_service.dart';

class NetworkLeaderboardCard extends StatefulWidget {
  final Map<String, List<LeaderboardEntry>> leaderboard;

  const NetworkLeaderboardCard({super.key, required this.leaderboard});

  @override
  State<NetworkLeaderboardCard> createState() => _NetworkLeaderboardCardState();
}

class _NetworkLeaderboardCardState extends State<NetworkLeaderboardCard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _domains = ['collector', 'reader', 'lender', 'cataloguer'];
  static const _domainIcons = [
    Icons.menu_book,
    Icons.auto_stories,
    Icons.handshake,
    Icons.shelves,
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
                  Text(
                    TranslationService.translate(context, 'leaderboard_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
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
                  children: _domains.map((domain) {
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
                    return _buildRankingList(entries);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateTabHeight() {
    final maxEntries = _domains
        .map((d) => (widget.leaderboard[d] ?? []).length)
        .fold(0, (a, b) => a > b ? a : b);
    // 56px per entry + padding, min 80 for empty state
    return (maxEntries * 56.0 + 8).clamp(80.0, 336.0);
  }

  Widget _buildRankingList(List<LeaderboardEntry> entries) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length.clamp(0, 6),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final rank = index + 1;
        return _buildRankRow(rank, entry);
      },
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
              'Lv.${entry.level}',
              style: TextStyle(
                fontSize: 12,
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
