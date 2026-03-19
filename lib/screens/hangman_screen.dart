import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/hangman_provider.dart';
import '../services/translation_service.dart';
import '../widgets/achievement_pop_animation.dart' show AchievementPopAnimation;
import '../widgets/hangman_keyboard.dart';
import '../widgets/hangman_painter.dart';
import '../widgets/hangman_word_display.dart';

class HangmanScreen extends StatefulWidget {
  const HangmanScreen({super.key});

  @override
  State<HangmanScreen> createState() => _HangmanScreenState();
}

class _HangmanScreenState extends State<HangmanScreen> {
  late HangmanProvider _provider;
  bool _achievementsShown = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<HangmanProvider>();
    _provider.addListener(_onProviderChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_provider.phase == HangmanPhase.complete) {
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
    if (_provider.phase == HangmanPhase.complete && !_achievementsShown) {
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
    } else if (_provider.phase == HangmanPhase.setup ||
        _provider.phase == HangmanPhase.playing) {
      _achievementsShown = false;
    }
  }

  void _onBackPressed() {
    if (_provider.phase != HangmanPhase.setup) {
      _provider.resetToSetup();
      _provider.loadDifficulties();
      return;
    }
    context.go('/games');
  }

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

  @override
  Widget build(BuildContext context) {
    final routeState = GoRouterState.of(context);
    if (routeState.uri.path == '/hangman' &&
        _provider.phase == HangmanPhase.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _provider.phase == HangmanPhase.complete) {
          _provider.resetToSetup();
          _provider.loadDifficulties();
        }
      });
    }

    return PopScope(
      canPop: _provider.phase == HangmanPhase.setup,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Consumer<HangmanProvider>(
        builder: (context, provider, _) {
          final theme = Theme.of(context);
          return KeyboardListener(
            focusNode: FocusNode(),
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  provider.phase == HangmanPhase.playing) {
                final char = event.character;
                if (char != null && char.length == 1) {
                  final lower = char.toLowerCase();
                  if (RegExp(r'^[a-z0-9]$').hasMatch(lower)) {
                    provider.guessChar(lower);
                  }
                }
              }
            },
            child: Scaffold(
            appBar: AppBar(
              title: Text(
                  TranslationService.translate(context, 'hangman_title')),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _onBackPressed,
              ),
              actions: provider.phase == HangmanPhase.playing
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Center(
                          child: Text(
                            provider.formattedTime,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.appBarTheme.foregroundColor ??
                                  theme.colorScheme.onPrimary,
                              fontFeatures: [
                                const FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]
                  : null,
            ),
            body: _buildBody(context, provider, theme),
          ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, HangmanProvider provider, ThemeData theme) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return Center(child: Text(provider.error!));
    }

    switch (provider.phase) {
      case HangmanPhase.setup:
        return _buildSetup(context, provider, theme);
      case HangmanPhase.playing:
        return _buildPlaying(context, provider, theme);
      case HangmanPhase.complete:
        return _HangmanCompleteView(
          provider: provider,
          onPlayAgain: provider.playAgain,
          onChangeDifficulty: () {
            provider.resetToSetup();
            provider.loadDifficulties();
          },
          onShowLeaderboard: () => _showLeaderboard(context),
        );
    }
  }

  // ── Setup Phase ──────────────────────────────────────────────

  Widget _buildSetup(
      BuildContext context, HangmanProvider provider, ThemeData theme) {
    if (provider.availableDifficulties.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                TranslationService.translate(
                    context, 'hangman_not_enough_books_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(
                    context, 'hangman_not_enough_books'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/scan'),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(
                  TranslationService.translate(context, 'action_scan_barcode'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/books/add'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  TranslationService.translate(context, 'action_add_book'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Visual preview + mode toggle
        Center(
          child: SizedBox(
            height: 120,
            child: HangmanPainterWidget(
              errors: 0,
              maxErrors: 6,
              visualMode: provider.visualMode,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: SegmentedButton<HangmanVisualMode>(
            segments: [
              ButtonSegment(
                value: HangmanVisualMode.classic,
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(TranslationService.translate(
                    context, 'hangman_style_classic')),
              ),
              ButtonSegment(
                value: HangmanVisualMode.books,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(TranslationService.translate(
                    context, 'hangman_style_books')),
              ),
            ],
            selected: {provider.visualMode},
            onSelectionChanged: (modes) {
              provider.setVisualMode(modes.first);
            },
          ),
        ),
        const SizedBox(height: 28),
        // Difficulty selection
        Text(
          TranslationService.translate(context, 'hangman_select_difficulty'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...provider.availableDifficulties.map((d) {
          final info = _difficultyInfo(d);
          final selected = provider.selectedDifficulty == d;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              elevation: selected ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: selected
                      ? info.color
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => provider.selectDifficulty(d),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: info.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(info.icon, color: info.color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              TranslationService.translate(
                                  context, 'hangman_difficulty_$d'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: selected
                                    ? info.color
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              TranslationService.translate(
                                  context, 'hangman_difficulty_${d}_desc'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle, color: info.color, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed:
              provider.selectedDifficulty != null ? provider.startGame : null,
          icon: const Icon(Icons.play_arrow),
          label:
              Text(TranslationService.translate(context, 'hangman_start')),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  // ── Playing Phase ────────────────────────────────────────────

  Widget _buildPlaying(
      BuildContext context, HangmanProvider provider, ThemeData theme) {
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: HangmanPainterWidget(
              errors: provider.errors,
              maxErrors: provider.maxErrors,
              visualMode: provider.visualMode,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                // Error dots + count, compact
                ...List.generate(provider.maxErrors, (i) {
                  final isError = i < provider.errors;
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isError
                            ? theme.colorScheme.error
                            : theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: isError
                              ? theme.colorScheme.error
                              : theme.colorScheme.outline
                                  .withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                if (provider.hintsAvailable > 0)
                  GestureDetector(
                    onTap: provider.authorHintAvailable ||
                            provider.coverHintAvailable
                        ? provider.useHint
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 16,
                          color: (provider.authorHintAvailable ||
                                  provider.coverHintAvailable)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${provider.hintsAvailable - provider.hintsUsed}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (provider.authorRevealed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                provider.author,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (provider.coverRevealed && provider.coverUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: CachedNetworkImage(
                    imageUrl: provider.coverUrl!,
                    height: 80,
                    width: 60,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HangmanWordDisplay(display: provider.display),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: HangmanKeyboard(
              guessedChars: provider.guessedChars,
              display: provider.display,
              onCharTap: provider.guessChar,
            ),
          ),
        ],
      ),
    );
  }

  static ({IconData icon, Color color}) _difficultyInfo(String d) {
    return switch (d) {
      'easy' => (icon: Icons.sentiment_satisfied, color: const Color(0xFF43A047)),
      'medium' => (icon: Icons.sentiment_neutral, color: const Color(0xFF1E88E5)),
      'hard' => (icon: Icons.local_fire_department, color: const Color(0xFFE53935)),
      _ => (icon: Icons.help_outline, color: Colors.grey),
    };
  }
}

// ── Animated Complete View ─────────────────────────────────────

class _HangmanCompleteView extends StatefulWidget {
  final HangmanProvider provider;
  final VoidCallback onPlayAgain;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onShowLeaderboard;

  const _HangmanCompleteView({
    required this.provider,
    required this.onPlayAgain,
    required this.onChangeDifficulty,
    required this.onShowLeaderboard,
  });

  @override
  State<_HangmanCompleteView> createState() => _HangmanCompleteViewState();
}

class _HangmanCompleteViewState extends State<_HangmanCompleteView>
    with TickerProviderStateMixin {
  late AnimationController _iconController;
  late AnimationController _contentController;
  late Animation<double> _iconScale;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    _iconController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.elasticOut),
    );

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

    _iconController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _contentController.forward();
    });
  }

  @override
  void dispose() {
    _iconController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    final score = provider.lastScore;
    final won = provider.won;

    final iconColor = won
        ? const Color(0xFFFFD700)
        : theme.colorScheme.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Animated icon ──
            AnimatedBuilder(
              animation: _iconController,
              builder: (context, _) {
                return Transform.scale(
                  scale: _iconScale.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.15),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.3),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      won ? Icons.emoji_events : Icons.menu_book_outlined,
                      size: 52,
                      color: iconColor,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // ── Content slides in ──
            SlideTransition(
              position: _contentSlide,
              child: FadeTransition(
                opacity: _contentFade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        won ? 'hangman_won' : 'hangman_lost',
                      ),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Title reveal
                    Text(
                      '"${provider.fullTitle}"',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (provider.author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        provider.author,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (provider.coverUrl != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: provider.coverUrl!,
                            height: 100,
                            width: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],

                    // Rank chip
                    if (provider.personalRank != null) ...[
                      const SizedBox(height: 16),
                      Chip(
                        avatar: Icon(
                          provider.isNewPersonalBest
                              ? Icons.star
                              : Icons.leaderboard,
                          size: 18,
                          color: provider.isNewPersonalBest
                              ? const Color(0xFFFFD700)
                              : theme.colorScheme.primary,
                        ),
                        label: Text(
                          provider.isNewPersonalBest
                              ? TranslationService.translate(
                                  context, 'hangman_new_best')
                              : '#${provider.personalRank}',
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Score card
                    if (score != null)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _statRow(
                                context,
                                theme,
                                Icons.stars_outlined,
                                'hangman_score',
                                score.formattedScore,
                              ),
                              _statRow(
                                context,
                                theme,
                                Icons.timer_outlined,
                                'hangman_time',
                                score.formattedTime,
                              ),
                              _statRow(
                                context,
                                theme,
                                Icons.close,
                                'hangman_errors',
                                '${score.errors}/${provider.maxErrors}',
                              ),
                              _statRow(
                                context,
                                theme,
                                Icons.lightbulb_outline,
                                'hangman_hints',
                                '${score.hintsUsed}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),

                    // Buttons
                    FilledButton.icon(
                      onPressed: widget.onPlayAgain,
                      icon: const Icon(Icons.replay),
                      label: Text(TranslationService.translate(
                          context, 'hangman_play_again')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onChangeDifficulty,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(TranslationService.translate(
                          context, 'hangman_back_to_menu')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: widget.onShowLeaderboard,
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: Text(TranslationService.translate(
                          context, 'hangman_leaderboard')),
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

  Widget _statRow(BuildContext context, ThemeData theme, IconData icon,
      String labelKey, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            TranslationService.translate(context, labelKey),
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard Bottom Sheet ───────────────────────────────────

class _LeaderboardSheet extends StatelessWidget {
  const _LeaderboardSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<HangmanProvider>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              TranslationService.translate(context, 'hangman_leaderboard'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // Top scores
            Expanded(
              child: provider.topScores.isEmpty
                  ? Center(
                      child: Text(
                        TranslationService.translate(
                            context, 'hangman_no_scores'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: provider.topScores.length,
                      itemBuilder: (context, index) {
                        final s = provider.topScores[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: index < 3
                                ? [
                                    const Color(0xFFFFD700),
                                    const Color(0xFFC0C0C0),
                                    const Color(0xFFCD7F32),
                                  ][index]
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: index < 3
                                    ? Colors.black87
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(s.formattedScore),
                          subtitle: Text(
                            '${TranslationService.translate(context, 'hangman_difficulty_${s.difficulty}')} - ${s.formattedTime}',
                          ),
                          trailing: s.won
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 20)
                              : const Icon(Icons.cancel,
                                  color: Colors.red, size: 20),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
