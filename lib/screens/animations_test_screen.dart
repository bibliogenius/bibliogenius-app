import 'package:flutter/material.dart';
import '../widgets/achievement_pop_animation.dart';
import '../widgets/goal_reached_animation.dart';
import '../widgets/badge_unlock_animation.dart';
import '../widgets/level_up_animation.dart';
import '../widgets/gamification_widgets.dart';
import '../widgets/book_complete_animation.dart';
import '../widgets/plus_one_animation.dart';
import '../services/translation_service.dart';

/// Demo screen to test all gamification animations
class AnimationsTestScreen extends StatelessWidget {
  const AnimationsTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'help_animation_tests'),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationService.translate(context, 'anim_gamification_title'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'anim_tap_to_test'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Achievement Pop
            _AnimationCard(
              title:
                  '🏆 ${TranslationService.translate(context, 'anim_achievement_pop')}',
              description: TranslationService.translate(
                context,
                'anim_achievement_pop_desc',
              ),
              color: Colors.amber,
              onTap: () {
                AchievementPopAnimation.show(
                  context,
                  achievementName: TranslationService.translate(
                    context,
                    'achievement_first_book',
                  ),
                  achievementIcon: Icons.auto_stories,
                  color: Colors.amber,
                );
              },
            ),

            const SizedBox(height: 16),

            // Goal Reached
            _AnimationCard(
              title:
                  '🎯 ${TranslationService.translate(context, 'anim_goal_reached')}',
              description: TranslationService.translate(
                context,
                'anim_goal_reached_desc',
              ),
              color: Colors.green,
              onTap: () {
                GoalReachedAnimation.show(
                  context,
                  goalType: 'yearly',
                  booksRead: 25,
                  customMessage: TranslationService.translate(
                    context,
                    'yearly_goal_reached',
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Badge Unlock
            _AnimationCard(
              title:
                  '🏅 ${TranslationService.translate(context, 'anim_badge_unlock')}',
              description: TranslationService.translate(
                context,
                'anim_badge_unlock_desc',
              ),
              color: Colors.purple,
              onTap: () {
                BadgeUnlockAnimation.show(
                  context,
                  badgeName: TranslationService.translate(
                    context,
                    'level_bibliophile',
                  ),
                  badgeAssetPath: 'assets/images/badges/bibliophile.svg',
                  badgeColor: const Color(0xFFFF9800),
                  subtitle: TranslationService.translate(
                    context,
                    'new_badge_unlocked',
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Level Up
            _AnimationCard(
              title:
                  '⬆️ ${TranslationService.translate(context, 'anim_level_up')}',
              description: TranslationService.translate(
                context,
                'anim_level_up_desc',
              ),
              color: Colors.blue,
              onTap: () {
                LevelUpAnimation.show(
                  context,
                  newLevel: 3,
                  levelLabel: trackLevelLabel(3, trackTierNames(context)),
                  trackName: TranslationService.translate(
                    context,
                    'track_reader',
                  ),
                  trackColor: trackTierColor(3),
                  trackIcon: Icons.menu_book,
                );
              },
            ),

            const SizedBox(height: 16),

            // Book Complete
            _AnimationCard(
              title:
                  '📚 ${TranslationService.translate(context, 'anim_book_complete')}',
              description: TranslationService.translate(
                context,
                'anim_book_complete_desc',
              ),
              color: Colors.teal,
              onTap: () {
                BookCompleteCelebration.show(
                  context,
                  bookTitle: 'The Great Gatsby',
                  xpEarned: 50,
                );
              },
            ),

            const SizedBox(height: 16),

            // Plus One
            _AnimationCard(
              title: TranslationService.translate(context, 'anim_plus_one'),
              description: TranslationService.translate(
                context,
                'anim_plus_one_desc',
              ),
              color: Colors.orange,
              onTap: () {
                PlusOneAnimation.show(context);
              },
            ),

            const SizedBox(height: 32),

            // Test multiple animations
            ElevatedButton.icon(
              onPressed: () async {
                // Resolve context-dependent labels before the async gaps.
                final collectorTier = trackLevelLabel(2, trackTierNames(context));
                // Trigger sequence of animations
                AchievementPopAnimation.show(
                  context,
                  achievementName: TranslationService.translate(
                    context,
                    'achievement_streak_7',
                  ),
                  achievementIcon: Icons.local_fire_department,
                  color: Colors.red,
                );

                await Future.delayed(const Duration(milliseconds: 1500));

                PlusOneAnimation.show(context);

                await Future.delayed(const Duration(milliseconds: 1500));

                LevelUpAnimation.show(
                  context,
                  newLevel: 2,
                  levelLabel: collectorTier,
                  trackName: TranslationService.translate(
                    context,
                    'track_collector',
                  ),
                  trackColor: trackTierColor(2),
                  trackIcon: Icons.collections_bookmark,
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(
                TranslationService.translate(context, 'anim_play_sequence'),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimationCard extends StatelessWidget {
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _AnimationCard({
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.play_circle_filled, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Icon(Icons.touch_app, color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
