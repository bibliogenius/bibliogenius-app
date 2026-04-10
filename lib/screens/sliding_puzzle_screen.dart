import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/sliding_puzzle_provider.dart';
import '../services/translation_service.dart';
import '../widgets/achievement_pop_animation.dart';
import '../widgets/puzzle_board_widget.dart';
import '../widgets/cached_book_cover.dart';

/// Sliding Puzzle screen with three phases:
/// 1. Setup - pick difficulty
/// 2. Playing - slide tiles to solve
/// 3. Complete - view score, play again
class SlidingPuzzleScreen extends StatefulWidget {
  const SlidingPuzzleScreen({super.key});

  @override
  State<SlidingPuzzleScreen> createState() => _SlidingPuzzleScreenState();
}

class _SlidingPuzzleScreenState extends State<SlidingPuzzleScreen> {
  late SlidingPuzzleProvider _provider;
  bool _achievementsShown = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<SlidingPuzzleProvider>();
    _provider.addListener(_onProviderChanged);
    _provider.subscribeToLeaderboardPush();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_provider.phase == PuzzlePhase.complete) {
        _provider.resetToSetup();
      }
      _provider.loadDifficulties();
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (_provider.phase == PuzzlePhase.complete && !_achievementsShown) {
      final achievements = _provider.lastScore?.newAchievements ?? [];
      if (achievements.isNotEmpty) {
        _achievementsShown = true;
        for (var i = 0; i < achievements.length; i++) {
          Future.delayed(Duration(milliseconds: i * 500), () {
            if (!mounted) return;
            AchievementPopAnimation.show(
              context,
              achievementName: TranslationService.translate(
                context,
                'achievement_${achievements[i]}',
              ),
            );
          });
        }
      }
    } else if (_provider.phase == PuzzlePhase.setup ||
        _provider.phase == PuzzlePhase.playing) {
      _achievementsShown = false;
    }
  }

  void _onBackPressed() {
    if (_provider.phase != PuzzlePhase.setup) {
      _provider.resetToSetup();
      _provider.loadDifficulties();
      return;
    }
    context.go('/games');
  }

  @override
  Widget build(BuildContext context) {
    final routeState = GoRouterState.of(context);
    if (routeState.uri.path == '/sliding-puzzle' &&
        _provider.phase == PuzzlePhase.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _provider.phase == PuzzlePhase.complete) {
          _provider.resetToSetup();
          _provider.loadDifficulties();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
        title: Text(
          TranslationService.translate(context, 'sliding_puzzle_title'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: TranslationService.translate(
                context, 'sliding_puzzle_scores_title'),
            onPressed: () => _showScores(context),
          ),
        ],
      ),
      body: Consumer<SlidingPuzzleProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _buildError(provider);
          }

          switch (provider.phase) {
            case PuzzlePhase.setup:
              return _buildSetup(provider);
            case PuzzlePhase.playing:
              return _buildPlaying(provider);
            case PuzzlePhase.complete:
              return _buildComplete(provider);
          }
        },
      ),
    );
  }

  Widget _buildError(SlidingPuzzleProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            provider.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => provider.loadDifficulties(),
            child: Text(
              TranslationService.translate(context, 'button_retry'),
            ),
          ),
        ],
      ),
    );
  }

  // ============ Setup Phase ============

  Widget _buildSetup(SlidingPuzzleProvider provider) {
    final difficulties = provider.availableDifficulties;

    if (difficulties.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_not_enough_books'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_intro'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_choose_difficulty'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...difficulties.map((d) => _buildDifficultyCard(provider, d)),
              const SizedBox(height: 8),
              _buildLeaderboardButton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: provider.selectedDifficulty != null
                      ? () => provider.startGame()
                      : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    TranslationService.translate(
                        context, 'sliding_puzzle_play'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDifficultyCard(
      SlidingPuzzleProvider provider, String difficulty) {
    final isSelected = provider.selectedDifficulty == difficulty;
    final info = _difficultyInfo(difficulty);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => provider.selectDifficulty(difficulty),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: isSelected
                ? LinearGradient(
                    colors: [info.color, info.colorEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : theme.colorScheme.surface,
            border: isSelected
                ? null
                : Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1.5,
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: info.color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Row(
            children: [
              Icon(
                info.icon,
                size: 32,
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(
                          context, 'sliding_puzzle_$difficulty'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ============ Playing Phase ============

  Widget _buildPlaying(SlidingPuzzleProvider provider) {
    return SafeArea(
      child: Column(
        children: [
          // Stats bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(
                  Icons.timer_outlined,
                  provider.formattedTime,
                  TranslationService.translate(
                      context, 'sliding_puzzle_time'),
                ),
                _buildStat(
                  Icons.swipe,
                  '${provider.moveCount}',
                  TranslationService.translate(
                      context, 'sliding_puzzle_moves'),
                ),
                _buildStat(
                  Icons.flag_outlined,
                  '${provider.parMoves}',
                  TranslationService.translate(
                      context, 'sliding_puzzle_par'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Board + reference image
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On wide screens, show reference image beside the board
                final isWide = constraints.maxWidth > 600;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: const PuzzleBoardWidget(),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: _buildReferenceImage(provider),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: const PuzzleBoardWidget(),
                        ),
                      ),
                    ),
                    _buildReferenceImageCompact(provider),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceImage(SlidingPuzzleProvider provider) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            TranslationService.translate(context, 'sliding_puzzle_reference'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 120,
              child: CachedBookCover(
                imageUrl: provider.board?.coverUrl ?? '',
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            provider.board?.title ?? '',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceImageCompact(SlidingPuzzleProvider provider) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: CachedBookCover(
                imageUrl: provider.board?.coverUrl ?? '',
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              provider.board?.title ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
        ),
      ],
    );
  }

  // ============ Complete Phase ============

  Widget _buildComplete(SlidingPuzzleProvider provider) {
    final score = provider.lastScore;
    final theme = Theme.of(context);
    final messageIndex = Random().nextInt(5);
    final congratsKey = 'puzzle_congrats_$messageIndex';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(context, congratsKey),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (provider.isNewPersonalBest) ...[
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(
                    context, 'puzzle_new_personal_best'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (score != null) _buildScoreCard(score, theme),
            if (provider.personalRank != null) ...[
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(
                        context, 'puzzle_rank_position')
                    .replaceAll('%s', '${provider.personalRank}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: 260,
              height: 48,
              child: FilledButton(
                onPressed: () => provider.playAgain(),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  TranslationService.translate(
                      context, 'sliding_puzzle_play_again'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                provider.resetToSetup();
                provider.loadDifficulties();
              },
              child: Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_change_difficulty'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard(
      dynamic score, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              score.normalizedScore.round().toString(),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              TranslationService.translate(context, 'sliding_puzzle_score'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildScoreDetail(
                  theme,
                  Icons.timer_outlined,
                  score.formattedTime,
                  TranslationService.translate(
                      context, 'sliding_puzzle_time'),
                ),
                _buildScoreDetail(
                  theme,
                  Icons.swipe,
                  '${score.moveCount}/${score.parMoves}',
                  TranslationService.translate(
                      context, 'sliding_puzzle_moves'),
                ),
                _buildScoreDetail(
                  theme,
                  Icons.speed,
                  score.difficulty,
                  TranslationService.translate(
                      context, 'sliding_puzzle_difficulty_label'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreDetail(
      ThemeData theme, IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleSmall),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ============ Scores ============

  Widget _buildLeaderboardButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showScores(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : Colors.amber.shade50,
          border: Border.all(
            color: Colors.amber.withValues(alpha: isDark ? 0.3 : 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.amber.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.emoji_events_rounded,
                  size: 22, color: Color(0xFFE0A030)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                TranslationService.translate(
                    context, 'puzzle_leaderboard_title'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  void _showScores(BuildContext context) {
    _provider.loadTopScores();
    _provider.loadNetworkLeaderboard();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: _provider,
        child: const _LeaderboardSheet(),
      ),
    );
  }

  // ============ Helpers ============

  _DifficultyInfo _difficultyInfo(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return const _DifficultyInfo(
          Icons.grid_3x3,
          Color(0xFF43A047),
          Color(0xFF66BB6A),
          '3x3 - 8 tiles',
        );
      case 'medium':
        return const _DifficultyInfo(
          Icons.grid_4x4,
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
          '4x4 - 15 tiles',
        );
      case 'hard':
        return const _DifficultyInfo(
          Icons.grid_on,
          Color(0xFFEF6C00),
          Color(0xFFFFA726),
          '5x5 - 24 tiles',
        );
      default:
        return const _DifficultyInfo(
            Icons.help_outline, Colors.grey, Colors.grey, '');
    }
  }
}

class _DifficultyInfo {
  final IconData icon;
  final Color color;
  final Color colorEnd;
  final String subtitle;

  const _DifficultyInfo(this.icon, this.color, this.colorEnd, this.subtitle);
}

// ============ Leaderboard Bottom Sheet ============

class _LeaderboardSheet extends StatefulWidget {
  const _LeaderboardSheet();

  @override
  State<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<_LeaderboardSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _difficultyFilter;

  static const _allDifficulties = ['easy', 'medium', 'hard'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title + refresh button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Consumer<SlidingPuzzleProvider>(
                builder: (context, provider, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                            context, 'puzzle_leaderboard_title'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (provider.isSyncingNetwork)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () => provider.loadNetworkLeaderboard(),
                        tooltip: TranslationService.translate(
                            context, 'puzzle_leaderboard_refreshing'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  text: TranslationService.translate(
                      context, 'puzzle_my_scores_tab'),
                ),
                Tab(
                  text: TranslationService.translate(
                      context, 'puzzle_network_tab'),
                ),
              ],
            ),
            // Difficulty filter chips
            _buildDifficultyFilters(theme),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildMyScores(scrollController),
                  _buildNetworkScores(scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDifficultyFilters(ThemeData theme) {
    return Consumer<SlidingPuzzleProvider>(
      builder: (context, provider, _) {
        final myDifficulties =
            provider.topScores.map((s) => s.difficulty).toSet();
        final networkDifficulties =
            provider.networkScores.map((e) => e.difficulty).toSet();
        final available = myDifficulties.union(networkDifficulties);

        if (available.length <= 1) return const SizedBox.shrink();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(TranslationService.translate(
                      context, 'filter_all')),
                  selected: _difficultyFilter == null,
                  onSelected: (_) =>
                      setState(() => _difficultyFilter = null),
                ),
              ),
              ..._allDifficulties
                  .where((d) => available.contains(d))
                  .map((d) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(TranslationService.translate(
                              context, 'sliding_puzzle_$d')),
                          selected: _difficultyFilter == d,
                          onSelected: (_) =>
                              setState(() => _difficultyFilter = d),
                        ),
                      )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyScores(ScrollController scrollController) {
    return Consumer<SlidingPuzzleProvider>(
      builder: (context, provider, _) {
        var scores = provider.topScores;
        if (_difficultyFilter != null) {
          scores = scores
              .where((s) => s.difficulty == _difficultyFilter)
              .toList();
        }

        if (scores.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_no_scores_yet'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[500],
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: scores.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final score = scores[index];
            final rank = index + 1;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _rankBadge(rank, theme),
              title: Text(
                TranslationService.translate(
                    context, 'sliding_puzzle_${score.difficulty}'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _formatDate(score.playedAt),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey[500]),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        score.formattedScore,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${score.formattedTime} - ${score.moveCount} moves',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNetworkScores(ScrollController scrollController) {
    return Consumer<SlidingPuzzleProvider>(
      builder: (context, provider, _) {
        var scores = provider.networkScores;
        if (_difficultyFilter != null) {
          scores = scores
              .where((e) => e.difficulty == _difficultyFilter)
              .toList();
        }

        if (provider.isSyncingNetwork && scores.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(
                        context, 'puzzle_leaderboard_refreshing'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[500],
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (scores.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TranslationService.translate(
                        context, 'puzzle_leaderboard_empty_network'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[500],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  IconButton(
                    onPressed: provider.isSyncingNetwork
                        ? null
                        : () => provider.loadNetworkLeaderboard(),
                    icon: const Icon(Icons.refresh),
                    tooltip: TranslationService.translate(
                        context, 'puzzle_leaderboard_refreshing'),
                  ),
                ],
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: scores.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = scores[index];
            final rank = index + 1;
            final isSelf = entry.isSelf;
            return Container(
              decoration: isSelf
                  ? BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: ListTile(
                contentPadding: isSelf
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : EdgeInsets.zero,
                leading: _rankBadge(rank, theme),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.libraryName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelf ? FontWeight.bold : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.person,
                          size: 16, color: theme.colorScheme.primary),
                    ],
                  ],
                ),
                subtitle: Text(
                  TranslationService.translate(
                      context, 'sliding_puzzle_${entry.difficulty}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
                trailing: Text(
                  entry.formattedScore,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSelf
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _rankBadge(int rank, ThemeData theme) {
    Color bgColor;
    Color textColor;
    switch (rank) {
      case 1:
        bgColor = const Color(0xFFFFD700);
        textColor = Colors.black87;
        break;
      case 2:
        bgColor = const Color(0xFFC0C0C0);
        textColor = Colors.black87;
        break;
      case 3:
        bgColor = const Color(0xFFCD7F32);
        textColor = Colors.white;
        break;
      default:
        bgColor = theme.colorScheme.surfaceContainerHigh;
        textColor = theme.colorScheme.onSurface;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
      ),
      alignment: Alignment.center,
      child: Text(
        '#$rank',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.length >= 10) {
      return dateStr.substring(0, 10);
    }
    return dateStr;
  }
}
