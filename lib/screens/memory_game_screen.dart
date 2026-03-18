import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/memory_game.dart';
import '../providers/memory_game_provider.dart';
import '../services/translation_service.dart';
import '../widgets/achievement_pop_animation.dart';
import '../widgets/memory_game_board.dart';

/// Memory Game screen with three phases:
/// 1. Setup — pick difficulty
/// 2. Playing — flip cards, find pairs
/// 3. Complete — view score, play again
class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  late MemoryGameProvider _provider;
  bool _achievementsShown = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<MemoryGameProvider>();
    _provider.addListener(_onProviderChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reset if returning to screen after a completed game
      if (_provider.phase == GamePhase.complete) {
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
    if (_provider.phase == GamePhase.complete && !_achievementsShown) {
      final achievements = _provider.lastScore?.newAchievements ?? [];
      if (achievements.isNotEmpty) {
        _achievementsShown = true;
        // Show achievements with a slight delay between each
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
    } else if (_provider.phase == GamePhase.setup ||
        _provider.phase == GamePhase.playing) {
      _achievementsShown = false;
    }
  }

  void _onBackPressed() {
    // If in-game or complete, go back to setup — don't navigate away
    if (_provider.phase != GamePhase.setup) {
      _provider.resetToSetup();
      _provider.loadDifficulties();
      return;
    }
    // From setup, navigate back to games hub
    context.go('/games');
  }

  @override
  Widget build(BuildContext context) {
    // Detect ShellRoute re-navigation: if GoRouterState changed to this
    // route while a game was complete, reset to setup.
    final routeState = GoRouterState.of(context);
    if (routeState.uri.path == '/memory-game' &&
        _provider.phase == GamePhase.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _provider.phase == GamePhase.complete) {
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
          TranslationService.translate(context, 'memory_game_title'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: TranslationService.translate(
                context, 'memory_leaderboard_title'),
            onPressed: () => _showLeaderboard(context),
          ),
        ],
      ),
      body: Consumer<MemoryGameProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _buildError(provider);
          }

          switch (provider.phase) {
            case GamePhase.setup:
              return _buildSetup(provider);
            case GamePhase.playing:
            case GamePhase.matchCheck:
              return _buildPlaying(provider);
            case GamePhase.complete:
              return _buildComplete(provider);
          }
        },
      ),
    );
  }

  Widget _buildError(MemoryGameProvider provider) {
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

  Widget _buildSetup(MemoryGameProvider provider) {
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
                    context, 'memory_game_not_enough_books'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isEnabled = provider.selectedDifficulty != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Text(
                TranslationService.translate(
                    context, 'memory_game_intro'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                TranslationService.translate(
                    context, 'memory_game_choose_difficulty'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...difficulties.map((d) => _buildDifficultyCard(provider, d)),
              const SizedBox(height: 8),
              // Leaderboard access button
              _buildLeaderboardButton(),
            ],
          ),
        ),
        // Play button — constrained width
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isEnabled ? 1.0 : 0.4,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    onTap: isEnabled ? provider.startGame : null,
                    borderRadius: BorderRadius.circular(28),
                    child: Ink(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          colors: isEnabled
                              ? const [
                                  Color(0xFF43A047), // Green
                                  Color(0xFF26A69A), // Teal
                                ]
                              : [Colors.grey.shade400, Colors.grey.shade400],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: isEnabled
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF43A047)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(
                                context, 'memory_game_play'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDifficultyCard(MemoryGameProvider provider, String difficulty) {
    final isSelected = provider.selectedDifficulty == difficulty;
    final info = _difficultyInfo(difficulty);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                    colors: [
                      info.color,
                      info.colorEnd,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: isDark
                        ? [
                            theme.colorScheme.surfaceContainerHigh,
                            theme.colorScheme.surfaceContainerHigh,
                          ]
                        : [
                            Colors.white,
                            info.color.withValues(alpha: 0.04),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: isSelected
                ? null
                : Border.all(
                    color: info.color.withValues(alpha: isDark ? 0.2 : 0.15),
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: info.color.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: info.color.withValues(alpha: isDark ? 0.05 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Decorative background icon
              Positioned(
                right: -2,
                bottom: -6,
                child: Icon(
                  info.icon,
                  size: 60,
                  color: (isSelected ? Colors.white : info.color)
                      .withValues(alpha: isSelected ? 0.18 : 0.10),
                ),
              ),
              // Content
              Row(
                children: [
                  // Icon badge
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : info.color.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      info.icon,
                      size: 26,
                      color: isSelected ? Colors.white : info.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                              context, 'memory_game_$difficulty'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          info.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.85)
                                : info.color.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Checkmark
                  if (isSelected)
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 20, color: Colors.white),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showLeaderboard(context),
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
                    context, 'memory_leaderboard_title'),
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

  // ============ Playing Phase ============

  Widget _buildPlaying(MemoryGameProvider provider) {
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
                  TranslationService.translate(context, 'memory_game_time'),
                ),
                _buildStat(
                  Icons.check_circle_outline,
                  '${provider.matchedPairs}/${provider.totalPairs}',
                  TranslationService.translate(context, 'memory_game_pairs'),
                ),
                _buildStat(
                  Icons.close,
                  '${provider.errors}',
                  TranslationService.translate(context, 'memory_game_errors'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Game board
          Expanded(
            child: MemoryGameBoard(
              cards: provider.cards,
              onCardTap: provider.flipCard,
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

  Widget _buildComplete(MemoryGameProvider provider) {
    final score = provider.lastScore;

    return _MemoryGameCompleteView(
      score: score,
      personalRank: provider.personalRank,
      isNewPersonalBest: provider.isNewPersonalBest,
      onPlayAgain: provider.playAgain,
      onChangeDifficulty: provider.resetToSetup,
      onShowLeaderboard: () => _showLeaderboard(context),
    );
  }

  // ============ Leaderboard ============

  void _showLeaderboard(BuildContext context) {
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
          Icons.sentiment_satisfied,
          Color(0xFF43A047),
          Color(0xFF66BB6A),
          '3 pairs - 3x2',
        );
      case 'medium':
        return const _DifficultyInfo(
          Icons.sentiment_neutral,
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
          '6 pairs - 3x4',
        );
      case 'hard':
        return const _DifficultyInfo(
          Icons.sentiment_dissatisfied,
          Color(0xFFEF6C00),
          Color(0xFFFFA726),
          '8 pairs - 4x4',
        );
      case 'expert':
        return const _DifficultyInfo(
          Icons.psychology,
          Color(0xFFE53935),
          Color(0xFFEF5350),
          '10 pairs - 5x4',
        );
      case 'master':
        return const _DifficultyInfo(
          Icons.local_fire_department,
          Color(0xFF7B1FA2),
          Color(0xFFAB47BC),
          '15 pairs - 5x6',
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

// ============ Animated Complete View ============

class _MemoryGameCompleteView extends StatefulWidget {
  final MemoryGameScore? score;
  final int? personalRank;
  final bool isNewPersonalBest;
  final VoidCallback onPlayAgain;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onShowLeaderboard;

  const _MemoryGameCompleteView({
    required this.score,
    this.personalRank,
    this.isNewPersonalBest = false,
    required this.onPlayAgain,
    required this.onChangeDifficulty,
    required this.onShowLeaderboard,
  });

  @override
  State<_MemoryGameCompleteView> createState() =>
      _MemoryGameCompleteViewState();
}

class _MemoryGameCompleteViewState extends State<_MemoryGameCompleteView>
    with TickerProviderStateMixin {
  late AnimationController _trophyController;
  late AnimationController _contentController;
  late AnimationController _shimmerController;
  late Animation<double> _trophyScale;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;
  late int _messageIndex;

  @override
  void initState() {
    super.initState();

    // Pick a random congratulation message
    _messageIndex = Random().nextInt(10);

    // Trophy entrance: scale up with elastic bounce
    _trophyController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _trophyScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _trophyController, curve: Curves.elasticOut),
    );

    // Content slide-up with fade
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOut),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOut),
    );

    // Shimmer loop on the trophy
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Stagger: trophy first, then content
    _trophyController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _contentController.forward();
    });
  }

  @override
  void dispose() {
    _trophyController.dispose();
    _contentController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  /// Pick a contextual message key based on performance
  String _congratsKey() {
    final score = widget.score;
    // Contextual messages for special cases
    if (score != null) {
      if (score.errors == 0) return 'memory_congrats_perfect';
      if (score.difficulty == 'master') return 'memory_congrats_master';
      if (score.difficulty == 'expert') return 'memory_congrats_expert';
    }
    // Varied generic messages (0-indexed)
    return 'memory_congrats_$_messageIndex';
  }

  Color _trophyColor() {
    final score = widget.score;
    if (score == null) return const Color(0xFFFFB300); // Amber
    if (score.errors == 0) return const Color(0xFFFFD700); // Gold
    if (score.errors <= 3) return const Color(0xFFE0A030); // Warm silver-gold
    return const Color(0xFFFFB300); // Amber (always warm/visible)
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = widget.score;
    final trophyColor = _trophyColor();
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Animated Trophy ----
            AnimatedBuilder(
              animation: _trophyController,
              builder: (context, _) {
                return Transform.scale(
                  scale: _trophyScale.value,
                  child: _buildTrophyOrb(trophyColor, isDark),
                );
              },
            ),
            const SizedBox(height: 24),

            // ---- Content (fades/slides in) ----
            SlideTransition(
              position: _contentSlide,
              child: FadeTransition(
                opacity: _contentFade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Congratulation message
                    Text(
                      TranslationService.translate(
                        context,
                        _congratsKey(),
                      ),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Rank info chip
                    if (widget.personalRank != null) ...[
                      const SizedBox(height: 12),
                      _buildRankChip(theme, colorScheme),
                    ],
                    const SizedBox(height: 24),

                    // Score card
                    if (score != null)
                      _buildScoreCard(score, colorScheme, theme, trophyColor),
                    const SizedBox(height: 32),

                    // Buttons
                    FilledButton.icon(
                      onPressed: widget.onPlayAgain,
                      icon: const Icon(Icons.replay),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'memory_game_play_again',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onChangeDifficulty,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'memory_game_change_difficulty',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: widget.onShowLeaderboard,
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'memory_leaderboard_title',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrophyOrb(Color trophyColor, bool isDark) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              center: Alignment.center,
              startAngle: 0,
              endAngle: pi * 2,
              transform: GradientRotation(_shimmerController.value * pi * 2),
              colors: [
                trophyColor.withValues(alpha: isDark ? 0.15 : 0.12),
                trophyColor.withValues(alpha: isDark ? 0.4 : 0.35),
                trophyColor.withValues(alpha: isDark ? 0.15 : 0.12),
                trophyColor.withValues(alpha: isDark ? 0.08 : 0.05),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: trophyColor.withValues(alpha: 0.35),
                blurRadius: 30,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Icon(
            Icons.emoji_events,
            size: 64,
            color: trophyColor,
          ),
        );
      },
    );
  }

  Widget _buildRankChip(ThemeData theme, ColorScheme colorScheme) {
    final isNewBest = widget.isNewPersonalBest;
    final rank = widget.personalRank!;

    final text = isNewBest
        ? TranslationService.translate(context, 'memory_rank_new_best')
        : TranslationService.translate(context, 'memory_rank_position')
            .replaceAll('%s', '$rank');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isNewBest
            ? Colors.amber.withValues(alpha: 0.15)
            : colorScheme.primaryContainer.withValues(alpha: 0.5),
        border: Border.all(
          color: isNewBest
              ? Colors.amber.withValues(alpha: 0.4)
              : colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNewBest ? Icons.star_rounded : Icons.leaderboard_outlined,
            size: 18,
            color: isNewBest ? Colors.amber : colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isNewBest ? Colors.amber.shade800 : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(
    MemoryGameScore score,
    ColorScheme colorScheme,
    ThemeData theme,
    Color accentColor,
  ) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerLow,
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildStatRow(
            Icons.star_rounded,
            TranslationService.translate(context, 'memory_game_score'),
            score.formattedScore,
            Colors.amber,
            theme,
          ),
          const Divider(height: 20),
          _buildStatRow(
            Icons.timer_outlined,
            TranslationService.translate(context, 'memory_game_time'),
            score.formattedTime,
            colorScheme.primary,
            theme,
          ),
          const Divider(height: 20),
          _buildStatRow(
            Icons.close,
            TranslationService.translate(context, 'memory_game_errors'),
            '${score.errors}',
            score.errors == 0 ? Colors.green : Colors.red.shade300,
            theme,
          ),
          const Divider(height: 20),
          _buildStatRow(
            Icons.speed,
            TranslationService.translate(
              context,
              'memory_game_difficulty_label',
            ),
            TranslationService.translate(
              context,
              'memory_game_${score.difficulty}',
            ),
            Colors.deepPurple.shade300,
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
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
  String? _difficultyFilter; // null = all

  static const _allDifficulties = ['easy', 'medium', 'hard', 'expert', 'master'];

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
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title + refresh button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Consumer<MemoryGameProvider>(
                builder: (context, provider, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                            context, 'memory_leaderboard_title'),
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
                            context, 'memory_leaderboard_refreshing'),
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
                      context, 'memory_my_scores_tab'),
                ),
                Tab(
                  text: TranslationService.translate(
                      context, 'memory_network_tab'),
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
    return Consumer<MemoryGameProvider>(
      builder: (context, provider, _) {
        // Collect available difficulties from actual data
        final myDifficulties =
            provider.topScores.map((s) => s.difficulty).toSet();
        final networkDifficulties =
            provider.networkScores.map((e) => e.difficulty).toSet();
        final available = myDifficulties.union(networkDifficulties);

        // Only show filter if more than one difficulty exists
        if (available.length <= 1) return const SizedBox.shrink();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // "All" chip
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(TranslationService.translate(
                      context, 'filter_all')),
                  selected: _difficultyFilter == null,
                  onSelected: (_) => setState(() => _difficultyFilter = null),
                ),
              ),
              // Difficulty chips (only those present in data)
              ..._allDifficulties
                  .where((d) => available.contains(d))
                  .map((d) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(TranslationService.translate(
                              context, 'memory_game_$d')),
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
    return Consumer<MemoryGameProvider>(
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
                TranslationService.translate(context, 'memory_no_scores_yet'),
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
                    context, 'memory_game_${score.difficulty}'),
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
                        '${score.formattedTime} - ${score.errors} err.',
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
    return Consumer<MemoryGameProvider>(
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
                        context, 'memory_leaderboard_refreshing'),
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
                        context, 'memory_leaderboard_empty_network'),
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
                        context, 'memory_leaderboard_refreshing'),
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
                contentPadding:
                    isSelf
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
                      context, 'memory_game_${entry.difficulty}'),
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
        '$rank',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: textColor,
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat.yMMMd().format(date);
    } catch (_) {
      return isoDate;
    }
  }
}

// Reuse the AnimatedBuilder from achievement_pop_animation.dart is not
// accessible here, so we use ListenableBuilder directly.
class AnimatedBuilder extends StatelessWidget {
  final Listenable animation;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: animation, builder: builder);
  }
}
