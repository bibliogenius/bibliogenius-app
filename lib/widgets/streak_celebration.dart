import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'dart:math' as math;

/// Streak milestone rewards configuration
class StreakMilestone {
  final int days;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;

  const StreakMilestone({
    required this.days,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

/// Predefined streak milestones with rewards
const List<StreakMilestone> streakMilestones = [
  StreakMilestone(
    days: 3,
    title: 'streak_milestone_3',
    description: 'streak_milestone_3_desc',
    icon: Icons.local_fire_department,
    color: Color(0xFFF59E0B),
    gradientColors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  ),
  StreakMilestone(
    days: 7,
    title: 'streak_milestone_7',
    description: 'streak_milestone_7_desc',
    icon: Icons.whatshot,
    color: Color(0xFFEF4444),
    gradientColors: [Color(0xFFEF4444), Color(0xFFDC2626)],
  ),
  StreakMilestone(
    days: 14,
    title: 'streak_milestone_14',
    description: 'streak_milestone_14_desc',
    icon: Icons.star,
    color: Color(0xFF8B5CF6),
    gradientColors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
  ),
  StreakMilestone(
    days: 30,
    title: 'streak_milestone_30',
    description: 'streak_milestone_30_desc',
    icon: Icons.emoji_events,
    color: Color(0xFFFFD700),
    gradientColors: [Color(0xFFFFD700), Color(0xFFFFA500)],
  ),
  StreakMilestone(
    days: 60,
    title: 'streak_milestone_60',
    description: 'streak_milestone_60_desc',
    icon: Icons.military_tech,
    color: Color(0xFFC0C0C0),
    gradientColors: [Color(0xFFE8E8E8), Color(0xFFC0C0C0)],
  ),
  StreakMilestone(
    days: 100,
    title: 'streak_milestone_100',
    description: 'streak_milestone_100_desc',
    icon: Icons.diamond,
    color: Color(0xFF0EA5E9),
    gradientColors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
  ),
  StreakMilestone(
    days: 365,
    title: 'streak_milestone_365',
    description: 'streak_milestone_365_desc',
    icon: Icons.auto_awesome,
    color: Color(0xFFEC4899),
    gradientColors: [Color(0xFFEC4899), Color(0xFFDB2777)],
  ),
];

/// Shows a streak celebration modal when appropriate
class StreakCelebration {
  static Future<void> showIfNeeded(
    BuildContext context, {
    required int currentStreak,
    required int longestStreak,
  }) async {
    if (currentStreak <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final lastShownDate = prefs.getString('streak_celebration_last_shown');
    final today = DateTime.now().toIso8601String().split('T')[0];

    // Only show once per day
    if (lastShownDate == today) return;

    // Check if we've reached a new milestone
    final lastCelebratedMilestone =
        prefs.getInt('streak_last_celebrated_milestone') ?? 0;
    StreakMilestone? newMilestone;

    for (final milestone in streakMilestones.reversed) {
      if (currentStreak >= milestone.days &&
          milestone.days > lastCelebratedMilestone) {
        newMilestone = milestone;
        break;
      }
    }

    await prefs.setString('streak_celebration_last_shown', today);

    if (!context.mounted) return;

    // Show milestone celebration or daily streak
    if (newMilestone != null) {
      await prefs.setInt('streak_last_celebrated_milestone', newMilestone.days);
      _showMilestoneCelebration(context, currentStreak, newMilestone);
    } else if (currentStreak > 1) {
      // Show simple daily streak animation
      _showDailyStreak(context, currentStreak);
    }
  }

  static void _showDailyStreak(BuildContext context, int currentStreak) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _DailyStreakToast(
        streak: currentStreak,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  static void _showMilestoneCelebration(
    BuildContext context,
    int currentStreak,
    StreakMilestone milestone,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MilestoneCelebrationSheet(
        streak: currentStreak,
        milestone: milestone,
      ),
    );
  }
}

/// Daily streak toast notification (appears at top)
class _DailyStreakToast extends StatefulWidget {
  final int streak;
  final VoidCallback onDismiss;

  const _DailyStreakToast({required this.streak, required this.onDismiss});

  @override
  State<_DailyStreakToast> createState() => _DailyStreakToastState();
}

class _DailyStreakToastState extends State<_DailyStreakToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -100,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        ),
        child: GestureDetector(
          onTap: () {
            _controller.reverse().then((_) => widget.onDismiss());
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Fire animation
                  _FireAnimation(size: 40),
                  const SizedBox(width: 16),
                  // Streak info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.streak} ${TranslationService.translate(context, 'days_streak')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          TranslationService.translate(context, 'keep_it_up'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  Icon(
                    Icons.close,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Milestone celebration bottom sheet
class _MilestoneCelebrationSheet extends StatefulWidget {
  final int streak;
  final StreakMilestone milestone;

  const _MilestoneCelebrationSheet({
    required this.streak,
    required this.milestone,
  });

  @override
  State<_MilestoneCelebrationSheet> createState() =>
      _MilestoneCelebrationSheetState();
}

class _MilestoneCelebrationSheetState extends State<_MilestoneCelebrationSheet>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _confettiController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _confettiController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _scaleController.forward();
    _confettiController.repeat();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Confetti particles
          ...List.generate(
            20,
            (index) => _ConfettiParticle(
              controller: _confettiController,
              index: index,
              color: widget.milestone.gradientColors[index % 2],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated icon
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.milestone.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.milestone.color.withValues(alpha: 0.5),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.milestone.icon,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                Text(
                  TranslationService.translate(context, widget.milestone.title),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: widget.milestone.color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Streak count
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FireAnimation(size: 32),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.streak} ${TranslationService.translate(context, 'days')}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Description
                Text(
                  TranslationService.translate(
                    context,
                    widget.milestone.description,
                  ),
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.milestone.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      TranslationService.translate(context, 'continue'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Next milestone hint
                _buildNextMilestoneHint(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextMilestoneHint(BuildContext context) {
    // Find next milestone
    StreakMilestone? nextMilestone;
    for (final m in streakMilestones) {
      if (m.days > widget.streak) {
        nextMilestone = m;
        break;
      }
    }

    if (nextMilestone == null) {
      return Text(
        TranslationService.translate(context, 'max_streak_reached'),
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[500],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final daysUntilNext = nextMilestone.days - widget.streak;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(nextMilestone.icon, size: 16, color: nextMilestone.color),
        const SizedBox(width: 8),
        Text(
          '${TranslationService.translate(context, 'next_reward_in')} $daysUntilNext ${TranslationService.translate(context, 'days')}',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

/// Animated fire icon
class _FireAnimation extends StatefulWidget {
  final double size;

  const _FireAnimation({required this.size});

  @override
  State<_FireAnimation> createState() => _FireAnimationState();
}

class _FireAnimationState extends State<_FireAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.1),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  const Color(0xFFFFD700),
                  const Color(0xFFF59E0B),
                  _controller.value,
                )!,
                Color.lerp(
                  const Color(0xFFEF4444),
                  const Color(0xFFDC2626),
                  _controller.value,
                )!,
              ],
            ).createShader(bounds),
            child: Icon(
              Icons.local_fire_department,
              size: widget.size,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/// Confetti particle for celebration
class _ConfettiParticle extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Color color;

  const _ConfettiParticle({
    required this.controller,
    required this.index,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final random = math.Random(index);
    final startX = random.nextDouble() * 300;
    final startY = random.nextDouble() * 100 - 50;
    final endY = 400 + random.nextDouble() * 100;
    final rotation = random.nextDouble() * 4 * math.pi;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;
        return Positioned(
          left: startX + math.sin(progress * math.pi * 2 + index) * 30,
          top: startY + (endY - startY) * progress,
          child: Transform.rotate(
            angle: rotation * progress,
            child: Opacity(
              opacity: (1 - progress).clamp(0.0, 1.0),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
