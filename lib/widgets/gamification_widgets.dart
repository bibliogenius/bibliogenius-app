import 'package:flutter/material.dart';
import '../models/gamification_status.dart';
import '../services/translation_service.dart';

/// A circular progress widget for displaying a single gamification track.
/// 
/// Shows a circular progress indicator with an icon in the center,
/// the track name, and the current level badge.
class TrackProgressWidget extends StatelessWidget {
  final TrackProgress track;
  final String trackName;
  final IconData icon;
  final Color color;
  final double size;

  const TrackProgressWidget({
    super.key,
    required this.track,
    required this.trackName,
    required this.icon,
    required this.color,
    this.size = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 6,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    color.withValues(alpha: 0.2),
                  ),
                ),
              ),
              // Progress circle
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: track.progress,
                  strokeWidth: 6,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // Center icon
              Container(
                width: size * 0.6,
                height: size * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: size * 0.35,
                ),
              ),
              // Level badge (top-right corner)
              if (track.level > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _getLevelColor(track.level),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      track.level.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          trackName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          '${track.current}/${track.nextThreshold}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Color _getLevelColor(int level) {
    switch (level) {
      case 1:
        return const Color(0xFFCD7F32); // Bronze
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFFFD700); // Gold
      default:
        return Colors.grey;
    }
  }
}

/// A row displaying all three gamification tracks.
class TracksProgressRow extends StatelessWidget {
  final GamificationStatus status;

  const TracksProgressRow({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TrackProgressWidget(
          track: status.collector,
          trackName: TranslationService.translate(context, 'track_collector'),
          icon: Icons.library_books,
          color: Colors.blue,
        ),
        TrackProgressWidget(
          track: status.reader,
          trackName: TranslationService.translate(context, 'track_reader'),
          icon: Icons.menu_book,
          color: Colors.green,
        ),
        TrackProgressWidget(
          track: status.lender,
          trackName: TranslationService.translate(context, 'track_lender'),
          icon: Icons.handshake,
          color: Colors.orange,
        ),
      ],
    );
  }
}

/// A widget displaying the current streak with a flame icon.
class StreakWidget extends StatelessWidget {
  final StreakInfo streak;

  const StreakWidget({
    super.key,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    if (!streak.hasStreak) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
          const SizedBox(width: 4),
          Text(
            '${streak.current}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            TranslationService.translate(context, 'days'),
            style: TextStyle(
              color: Colors.orange.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A premium card showing gamification summary with glassmorphism design.
class GamificationSummaryCard extends StatelessWidget {
  final GamificationStatus status;
  final VoidCallback? onTap;

  const GamificationSummaryCard({
    super.key,
    required this.status,
    this.onTap,
  });

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
            ? [
                const Color(0xFF1a1a2e),
                const Color(0xFF16213e),
              ]
            : [
                Colors.white,
                const Color(0xFFF5F7FA),
              ],
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and streak
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.emoji_events,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(context, 'your_progress'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      StreakWidget(streak: status.streak),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Tracks with enhanced layout
                  TracksProgressRow(status: status),
                  
                  // Reading goal progress (if enabled)
                  if (status.config.readingGoalYearly > 0) ...[
                    const SizedBox(height: 20),
                    _buildReadingGoalSection(context),
                  ],
                  
                  // Achievements section
                  if (status.hasAchievements) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark 
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.star,
                                size: 16,
                                color: Colors.amber[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                TranslationService.translate(context, 'recent_achievements'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: status.recentAchievements
                                .take(3)
                                .map((id) => _buildAchievementChip(context, id))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingGoalSection(BuildContext context) {
    final progress = status.config.goalProgress;
    final current = status.config.readingGoalProgress;
    final goal = status.config.readingGoalYearly;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            Text(
              '$current / $goal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementChip(BuildContext context, String id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.2),
            Colors.orange.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getAchievementIcon(id),
            size: 14,
            color: Colors.amber[700],
          ),
          const SizedBox(width: 4),
          Text(
            _getAchievementName(context, id),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.amber[800],
            ),
          ),
        ],
      ),
    );
  }

  String _getAchievementName(BuildContext context, String id) {
    // Try to translate, fallback to formatted ID
    final key = 'achievement_$id';
    final translated = TranslationService.translate(context, key);
    if (translated == key) {
      // Not translated, format the ID
      return id.replaceAll('_', ' ').split(' ').map((word) => 
        word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : ''
      ).join(' ');
    }
    return translated;
  }

  IconData _getAchievementIcon(String id) {
    if (id.contains('collector')) return Icons.library_books;
    if (id.contains('reader')) return Icons.menu_book;
    if (id.contains('lender') || id.contains('loan')) return Icons.handshake;
    if (id.contains('streak')) return Icons.local_fire_department;
    if (id.contains('scan')) return Icons.qr_code_scanner;
    if (id.contains('first')) return Icons.star;
    if (id.contains('goal')) return Icons.flag;
    return Icons.emoji_events;
  }
}
