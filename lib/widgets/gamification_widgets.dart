import 'package:flutter/material.dart';
import '../models/gamification_status.dart';
import '../services/translation_service.dart';

class BadgeInfo {
  final String assetPath;
  final String translationKey;
  final Color color;
  final Color secondaryColor;

  BadgeInfo({
    required this.assetPath,
    required this.translationKey,
    required this.color,
    required this.secondaryColor,
  });
}

BadgeInfo getBadgeInfo(int level) {
  switch (level) {
    case 0:
      return BadgeInfo(
        assetPath: 'assets/images/badges/curieux.png',
        translationKey: 'level_curieux',
        color: const Color(0xFF4CAF50), // Green
        secondaryColor: const Color(0xFF81C784),
      );
    case 1:
      return BadgeInfo(
        assetPath: 'assets/images/badges/initie.png',
        translationKey: 'level_initie',
        color: const Color(0xFF2196F3), // Blue
        secondaryColor: const Color(0xFF64B5F6),
      );
    case 2:
      return BadgeInfo(
        assetPath: 'assets/images/badges/bibliophile.png',
        translationKey: 'level_bibliophile',
        color: const Color(0xFFFF9800), // Orange
        secondaryColor: const Color(0xFFFFB74D),
      );
    case 3:
    default:
      return BadgeInfo(
        assetPath: 'assets/images/badges/erudit.png',
        translationKey: 'level_erudit',
        color: const Color(0xFFFFC107), // Gold
        secondaryColor: const Color(0xFFFFD54F),
      );
  }
}

class BadgeCollectionWidget extends StatelessWidget {
  final int maxTrackLevel;

  const BadgeCollectionWidget({
    super.key,
    required this.maxTrackLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 8.0, bottom: 12.0),
          child: Text(
            TranslationService.translate(context, 'badge_collection').toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(4, (index) {
                final badgeInfo = getBadgeInfo(index);
                final isUnlocked = maxTrackLevel >= index;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 70,
                        height: 70,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Background circle (like track background)
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isUnlocked 
                                    ? badgeInfo.color.withValues(alpha: 0.1) 
                                    : Colors.grey.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isUnlocked 
                                      ? badgeInfo.color.withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.2),
                                  width: 3,
                                ),
                              ),
                            ),
                            // Badge icon
                            ColorFiltered(
                              colorFilter: isUnlocked 
                                  ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                                  : const ColorFilter.matrix(<double>[
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0, 0, 0, 1, 0,
                                    ]),
                              child: Opacity(
                                opacity: isUnlocked ? 1.0 : 0.5,
                                child: Image.asset(
                                  badgeInfo.assetPath,
                                  width: 32,
                                  height: 32,
                                  filterQuality: FilterQuality.high,
                                  isAntiAlias: true,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.emoji_events, 
                                    size: 28, 
                                    color: Colors.grey[400]
                                  ),
                                ),
                              ),
                            ),
                            // Lock icon for locked badges
                            if (!isUnlocked)
                              Positioned(
                                bottom: 0,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.lock,
                                    size: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: Text(
                          TranslationService.translate(context, badgeInfo.translationKey).split(' ').last,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                            color: isUnlocked ? badgeInfo.color : Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ),
      ],
    );
  }
}

class CurrentBadgeWidget extends StatefulWidget {
  final int maxTrackLevel;

  const CurrentBadgeWidget({
    super.key,
    required this.maxTrackLevel,
  });

  @override
  State<CurrentBadgeWidget> createState() => _CurrentBadgeWidgetState();
}

class _CurrentBadgeWidgetState extends State<CurrentBadgeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeInfo = getBadgeInfo(widget.maxTrackLevel);
    final isPrestige = widget.maxTrackLevel > 3;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            badgeInfo.color.withValues(alpha: 0.1),
            badgeInfo.secondaryColor.withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: badgeInfo.color.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeInfo.color.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background decorative circle
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeInfo.secondaryColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
            child: Column(
              children: [
                // Level Name Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                    border: Border.all(
                      color: badgeInfo.color.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    isPrestige 
                        ? '${TranslationService.translate(context, badgeInfo.translationKey)} ${widget.maxTrackLevel}' 
                        : TranslationService.translate(context, badgeInfo.translationKey),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: badgeInfo.color,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Badge Image
                ScaleTransition(
                  scale: isPrestige ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: badgeInfo.color.withValues(alpha: isPrestige ? 0.6 : 0.4),
                          blurRadius: isPrestige ? 30 : 20,
                          spreadRadius: isPrestige ? 5 : 0,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      badgeInfo.assetPath,
                      width: 140,
                      height: 140,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: badgeInfo.color.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.emoji_events,
                            size: 64,
                            color: badgeInfo.color,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Current Level Label
                Text(
                  TranslationService.translate(context, 'your_current_level').toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


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
    this.size = 70.0,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use Row for wide screens, Wrap for narrow ones
        if (constraints.maxWidth > 400) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TrackProgressWidget(
                  track: status.collector,
                  trackName: TranslationService.translate(context, 'track_collector'),
                  icon: Icons.collections_bookmark,
                  color: Colors.blue,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.reader,
                  trackName: TranslationService.translate(context, 'track_reader'),
                  icon: Icons.menu_book,
                  color: Colors.green,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.lender,
                  trackName: TranslationService.translate(context, 'track_lender'),
                  icon: Icons.volunteer_activism,
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.cataloguer,
                  trackName: TranslationService.translate(context, 'track_cataloguer'),
                  icon: Icons.list_alt,
                  color: Colors.purple,
                ),
              ),
            ],
          );
        } else {
          // Wrap for narrow screens
          return Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 16,
            runSpacing: 12,
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
              TrackProgressWidget(
                track: status.cataloguer,
                trackName: TranslationService.translate(context, 'track_cataloguer'),
                icon: Icons.sort,
                color: Colors.purple,
              ),
            ],
          );
        }
      },
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
                  
                  // Badge Collection
                  BadgeCollectionWidget(maxTrackLevel: status.maxTrackLevel),
                   
                  const SizedBox(height: 24),
                  const Divider(height: 1, indent: 24, endIndent: 24),
                  const SizedBox(height: 24),

                  // Tracks with enhanced layout
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: TracksProgressRow(status: status),
                  ),
                  
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
