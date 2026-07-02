import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/memory_game.dart';
import '../providers/memory_game_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/achievement_pop_animation.dart';
import '../widgets/app_snack_bar.dart';
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
    _provider.subscribeToLeaderboardPush();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reset if returning to screen after a completed game
      if (_provider.phase == GamePhase.complete) {
        _provider.resetToSetup();
      }
      _provider.loadDifficulties();
      // Preload local top scores so each tier can show its best time.
      _provider.loadTopScores();
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
        title: Text(TranslationService.translate(context, 'memory_game_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: TranslationService.translate(
              context,
              'memory_leaderboard_title',
            ),
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
            child: Text(TranslationService.translate(context, 'button_retry')),
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
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                  context,
                  'memory_game_not_enough_books',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final themeStyle = context.watch<ThemeProvider>().themeStyle;
    final selected = provider.selectedDifficulty;
    final isEnabled = selected != null;

    // The Play button adopts the selected tier's color and names it, e.g.
    // "Play · Hard", so the choice reads back at the point of action.
    final playInfo = isEnabled ? _difficultyInfo(selected) : null;
    final playColors = playInfo != null
        ? [playInfo.color, playInfo.colorEnd]
        : [Colors.grey.shade400, Colors.grey.shade400];
    final playLabel = isEnabled
        ? '${TranslationService.translate(context, 'memory_game_play')} · '
              '${TranslationService.translate(context, 'memory_game_$selected')}'
        : TranslationService.translate(context, 'memory_game_play');

    return DecoratedBox(
      // Sit the page on the app's signature soft gradient (same as the
      // dashboard) instead of a flat surface, tying the game to the app shell.
      decoration: BoxDecoration(
        gradient: AppDesign.pageGradientForTheme(themeStyle),
      ),
      child: Column(
        children: [
          Expanded(
            // Cap the width so the desktop side gutters match the other pages.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDesign.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'memory_game_intro',
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeading(theme, themeStyle),
                    const SizedBox(height: 16),
                    ...difficulties.map(
                      (d) => _buildDifficultyCard(provider, d),
                    ),
                    const SizedBox(height: 8),
                    // Leaderboard access button
                    _buildLeaderboardButton(),
                  ],
                ),
              ),
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
                            colors: playColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: playInfo != null
                              ? [
                                  BoxShadow(
                                    color: playInfo.color.withValues(
                                      alpha: 0.4,
                                    ),
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
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                playLabel,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  fontSize: 17,
                                ),
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
      ),
    );
  }

  /// Section heading with the app's accent bar (matches the dashboard sections).
  Widget _buildSectionHeading(ThemeData theme, String themeStyle) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 5,
            height: 26,
            decoration: BoxDecoration(
              gradient: AppDesign.sectionAccentGradient(themeStyle),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            TranslationService.translate(
              context,
              'memory_game_choose_difficulty',
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyCard(MemoryGameProvider provider, String difficulty) {
    final isSelected = provider.selectedDifficulty == difficulty;
    final info = _difficultyInfo(difficulty);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final label = TranslationService.translate(
      context,
      'memory_game_$difficulty',
    );
    final subtitle = TranslationService.translate(
      context,
      'memory_game_tier_subtitle',
    ).replaceAll('{pairs}', '${info.pairs}').replaceAll('{grid}', info.grid);

    // Soft pastel wash over the theme surface, stronger when the tier is picked.
    final surface = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;
    final tint = Color.alphaBlend(
      info.color.withValues(
        alpha: isSelected ? (isDark ? 0.30 : 0.16) : (isDark ? 0.20 : 0.10),
      ),
      surface,
    );
    // Contrast-vetted subtitle color (darker shade in light mode, lighter in
    // dark mode) so the colored cards stay readable.
    final subtitleColor = isDark ? info.colorEnd : info.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$label, $subtitle',
        child: ScaleOnTap(
          onTap: () => provider.selectDifficulty(difficulty),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? info.color
                    : info.color.withValues(alpha: isDark ? 0.28 : 0.20),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: info.color.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: info.color.withValues(
                          alpha: isDark ? 0.06 : 0.08,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Left accent bar (stretches to the card's full height).
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 6, color: info.color),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // Icon badge
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                color: isSelected ? info.color : surface,
                                boxShadow: isSelected
                                    ? null
                                    : AppDesign.subtleShadow,
                              ),
                              child: Icon(
                                info.icon,
                                size: 24,
                                color: isSelected ? Colors.white : info.color,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Title + subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: subtitleColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Trailing: check when selected, else difficulty gauge.
                            if (isSelected)
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: info.color,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              )
                            else
                              _difficultyGauge(info),
                          ],
                        ),
                        // Expanded detail panel: grid preview, card count, best time.
                        if (isSelected)
                          _buildTierDetail(provider, difficulty, info, surface),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Detail panel revealed when a tier is expanded: a grid preview, the total
  /// card count, and the player's best time for that difficulty.
  Widget _buildTierDetail(
    MemoryGameProvider provider,
    String difficulty,
    _DifficultyInfo info,
    Color surface,
  ) {
    final theme = Theme.of(context);
    final best = provider.bestTimeFor(difficulty);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.grid_view_rounded, color: info.color, size: 26),
            ),
            _detailDivider(theme),
            Expanded(
              child: _detailStat(
                theme,
                '${info.pairs * 2}',
                TranslationService.translate(
                  context,
                  'memory_game_cards_label',
                ),
              ),
            ),
            _detailDivider(theme),
            Expanded(
              child: _detailStat(
                theme,
                best ?? '—',
                TranslationService.translate(context, 'memory_game_best_label'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 34,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _detailStat(ThemeData theme, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Five-dot gauge that reads a tier's relative difficulty at a glance — a
  /// playful meter using the tier's own accent color.
  Widget _difficultyGauge(_DifficultyInfo info) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < info.level;
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? info.color : info.color.withValues(alpha: 0.18),
          ),
        );
      }),
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
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 22,
                color: Color(0xFFE0A030),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                TranslationService.translate(
                  context,
                  'memory_leaderboard_title',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
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
          icon: Icons.sentiment_satisfied,
          color: Color(0xFF43A047),
          colorEnd: Color(0xFF66BB6A),
          dark: Color(0xFF2E7D32),
          pairs: 3,
          grid: '3×2',
          level: 1,
        );
      case 'medium':
        return const _DifficultyInfo(
          icon: Icons.sentiment_neutral,
          color: Color(0xFF1E88E5),
          colorEnd: Color(0xFF42A5F5),
          dark: Color(0xFF1565C0),
          pairs: 6,
          grid: '3×4',
          level: 2,
        );
      case 'hard':
        return const _DifficultyInfo(
          icon: Icons.sentiment_dissatisfied,
          color: Color(0xFFEF6C00),
          colorEnd: Color(0xFFFFA726),
          dark: Color(0xFFC2410C),
          pairs: 8,
          grid: '4×4',
          level: 3,
        );
      case 'expert':
        return const _DifficultyInfo(
          icon: Icons.psychology,
          color: Color(0xFFE53935),
          colorEnd: Color(0xFFEF5350),
          dark: Color(0xFFC62828),
          pairs: 10,
          grid: '5×4',
          level: 4,
        );
      case 'master':
        return const _DifficultyInfo(
          icon: Icons.local_fire_department,
          color: Color(0xFF7B1FA2),
          colorEnd: Color(0xFFAB47BC),
          dark: Color(0xFF6A1B9A),
          pairs: 15,
          grid: '5×6',
          level: 5,
        );
      default:
        return const _DifficultyInfo(
          icon: Icons.help_outline,
          color: Colors.grey,
          colorEnd: Colors.grey,
          dark: Color(0xFF616161),
          pairs: 0,
          grid: '',
          level: 0,
        );
    }
  }
}

class _DifficultyInfo {
  final IconData icon;
  final Color color;
  final Color colorEnd;

  /// Contrast-vetted darker shade, used for subtitle text on the light card
  /// wash so the colored cards stay readable (WCAG AA).
  final Color dark;

  /// Number of pairs for this tier (card count is `pairs * 2`).
  final int pairs;

  /// Grid layout label, e.g. "4×4".
  final String grid;

  /// Relative difficulty on a 1-5 scale, drives the difficulty gauge.
  final int level;

  const _DifficultyInfo({
    required this.icon,
    required this.color,
    required this.colorEnd,
    required this.dark,
    required this.pairs,
    required this.grid,
    required this.level,
  });
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
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
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
                      TranslationService.translate(context, _congratsKey()),
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
                    OutlinedButton.icon(
                      onPressed: widget.onShowLeaderboard,
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'memory_leaderboard_title',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(200, 48),
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
          child: Icon(Icons.emoji_events, size: 64, color: trophyColor),
        );
      },
    );
  }

  Widget _buildRankChip(ThemeData theme, ColorScheme colorScheme) {
    final isNewBest = widget.isNewPersonalBest;
    final rank = widget.personalRank!;

    final text = isNewBest
        ? TranslationService.translate(context, 'memory_rank_new_best')
        : TranslationService.translate(
            context,
            'memory_rank_position',
          ).replaceAll('%s', '$rank');

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
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
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

  static const _allDifficulties = [
    'easy',
    'medium',
    'hard',
    'expert',
    'master',
  ];

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

  Future<void> _refreshNetworkLeaderboard(MemoryGameProvider provider) async {
    await provider.refreshNetworkLeaderboard();
    if (!mounted) return;
    if (provider.lastRefreshTimedOut) {
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'leaderboard_sync_timeout'),
      );
    }
  }

  void _confirmResetScores(BuildContext context, MemoryGameProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'reset_scores')),
        content: Text(
          TranslationService.translate(context, 'reset_scores_confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              provider.resetScores();
            },
            child: Text(
              TranslationService.translate(context, 'confirm'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
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
                          context,
                          'memory_leaderboard_title',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _confirmResetScores(context, provider),
                      tooltip: TranslationService.translate(
                        context,
                        'reset_scores',
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
                        onPressed: () => _refreshNetworkLeaderboard(provider),
                        tooltip: TranslationService.translate(
                          context,
                          'memory_leaderboard_refreshing',
                        ),
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
                    context,
                    'memory_my_scores_tab',
                  ),
                ),
                Tab(
                  text: TranslationService.translate(
                    context,
                    'memory_network_tab',
                  ),
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
        final myDifficulties = provider.topScores
            .map((s) => s.difficulty)
            .toSet();
        final networkDifficulties = provider.networkScores
            .map((e) => e.difficulty)
            .toSet();
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
                  label: Text(
                    TranslationService.translate(context, 'filter_all'),
                  ),
                  selected: _difficultyFilter == null,
                  onSelected: (_) => setState(() => _difficultyFilter = null),
                ),
              ),
              // Difficulty chips (only those present in data)
              ..._allDifficulties
                  .where((d) => available.contains(d))
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          TranslationService.translate(
                            context,
                            'memory_game_$d',
                          ),
                        ),
                        selected: _difficultyFilter == d,
                        onSelected: (_) =>
                            setState(() => _difficultyFilter = d),
                      ),
                    ),
                  ),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
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
                  context,
                  'memory_game_${score.difficulty}',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _formatDate(score.playedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
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
                      context,
                      'memory_leaderboard_refreshing',
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
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
                      context,
                      'memory_leaderboard_empty_network',
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  IconButton(
                    onPressed: provider.isSyncingNetwork
                        ? null
                        : () => _refreshNetworkLeaderboard(provider),
                    icon: const Icon(Icons.refresh),
                    tooltip: TranslationService.translate(
                      context,
                      'memory_leaderboard_refreshing',
                    ),
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
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
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
                          fontWeight: isSelf
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.person,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  TranslationService.translate(
                    context,
                    'memory_game_${entry.difficulty}',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
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
