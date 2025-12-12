/// Gamification status model matching the new V3 backend API.
/// 
/// This model represents the user's gamification progress across
/// three distinct tracks: Collector, Reader, and Lender.
library;

/// Progress information for a single gamification track.
class TrackProgress {
  final int level;           // 0=None, 1=Bronze, 2=Silver, 3=Gold
  final double progress;     // 0.0 to 1.0 progress to next level
  final int current;         // Current value (books, reads, loans)
  final int nextThreshold;   // Next level threshold

  const TrackProgress({
    required this.level,
    required this.progress,
    required this.current,
    required this.nextThreshold,
  });

  factory TrackProgress.fromJson(Map<String, dynamic> json) {
    return TrackProgress(
      level: json['level'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      current: (json['current'] as num?)?.toInt() ?? 0,
      nextThreshold: json['next_threshold'] as int? ?? 0,
    );
  }

  /// Returns the level name based on current level.
  String get levelName {
    switch (level) {
      case 1:
        return 'Bronze';
      case 2:
        return 'Silver';
      case 3:
        return 'Gold';
      default:
        return 'Novice';
    }
  }

  /// Returns true if this track has reached max level.
  bool get isMaxLevel => level >= 3;
}

/// Streak information for daily activity tracking.
class StreakInfo {
  final int current;
  final int longest;

  const StreakInfo({
    required this.current,
    required this.longest,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> json) {
    return StreakInfo(
      current: json['current'] as int? ?? 0,
      longest: json['longest'] as int? ?? 0,
    );
  }

  /// Returns true if user has an active streak.
  bool get hasStreak => current > 0;
}

/// Gamification configuration for the current user.
class GamificationConfig {
  final String achievementsStyle;  // 'minimal', 'fun', 'professional'
  final int readingGoalYearly;
  final int readingGoalProgress;

  const GamificationConfig({
    required this.achievementsStyle,
    required this.readingGoalYearly,
    required this.readingGoalProgress,
  });

  factory GamificationConfig.fromJson(Map<String, dynamic> json) {
    return GamificationConfig(
      achievementsStyle: json['achievements_style'] as String? ?? 'minimal',
      readingGoalYearly: json['reading_goal_yearly'] as int? ?? 12,
      readingGoalProgress: json['reading_goal_progress'] as int? ?? 0,
    );
  }

  /// Returns progress toward yearly reading goal as percentage (0.0 to 1.0).
  double get goalProgress {
    if (readingGoalYearly <= 0) return 0.0;
    return (readingGoalProgress / readingGoalYearly).clamp(0.0, 1.0);
  }
}

/// Complete gamification status for a user.
/// 
/// Contains all three tracks, streak info, recent achievements,
/// and configuration. Also includes legacy fields for backward
/// compatibility with older UI components.
class GamificationStatus {
  final TrackProgress collector;
  final TrackProgress reader;
  final TrackProgress lender;
  final TrackProgress cataloguer;
  final StreakInfo streak;
  final List<String> recentAchievements;
  final GamificationConfig config;
  
  // Legacy fields for backward compatibility
  final String level;
  final int loansCount;
  final int editsCount;
  final double nextLevelProgress;
  final String badgeUrl;

  const GamificationStatus({
    required this.collector,
    required this.reader,
    required this.lender,
    required this.cataloguer,
    required this.streak,
    required this.recentAchievements,
    required this.config,
    required this.level,
    required this.loansCount,
    required this.editsCount,
    required this.nextLevelProgress,
    required this.badgeUrl,
  });

  factory GamificationStatus.fromJson(Map<String, dynamic> json) {
    final tracks = json['tracks'] as Map<String, dynamic>? ?? {};
    
    return GamificationStatus(
      collector: TrackProgress.fromJson(
        tracks['collector'] as Map<String, dynamic>? ?? {},
      ),
      reader: TrackProgress.fromJson(
        tracks['reader'] as Map<String, dynamic>? ?? {},
      ),
      lender: TrackProgress.fromJson(
        tracks['lender'] as Map<String, dynamic>? ?? {},
      ),
      cataloguer: TrackProgress.fromJson(
        tracks['cataloguer'] as Map<String, dynamic>? ?? {},
      ),
      streak: StreakInfo.fromJson(
        json['streak'] as Map<String, dynamic>? ?? {},
      ),
      recentAchievements: (json['recent_achievements'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      config: GamificationConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? {},
      ),
      // Legacy fields
      level: json['level'] as String? ?? 'Member',
      loansCount: (json['loans_count'] as num?)?.toInt() ?? 0,
      editsCount: (json['edits_count'] as num?)?.toInt() ?? 0,
      nextLevelProgress: (json['next_level_progress'] as num?)?.toDouble() ?? 0.0,
      badgeUrl: json['badge_url'] as String? ?? 'assets/badges/member.png',
    );
  }

  /// Returns the highest level achieved across all tracks.
  int get maxTrackLevel => [collector.level, reader.level, lender.level, cataloguer.level]
      .reduce((a, b) => a > b ? a : b);

  /// Returns true if user has any achievements.
  bool get hasAchievements => recentAchievements.isNotEmpty;

  /// Default empty status for initial state.
  static GamificationStatus get empty => const GamificationStatus(
    collector: TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 10),
    reader: TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 5),
    lender: TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 5),
    cataloguer: TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 10),
    streak: StreakInfo(current: 0, longest: 0),
    recentAchievements: [],
    config: GamificationConfig(
      achievementsStyle: 'minimal',
      readingGoalYearly: 12,
      readingGoalProgress: 0,
    ),
    level: 'Member',
    loansCount: 0,
    editsCount: 0,
    nextLevelProgress: 0.0,
    badgeUrl: 'assets/badges/member.png',
  );
}
