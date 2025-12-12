import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/gamification_status.dart';

void main() {
  group('TrackProgress', () {
    test('fromJson parses correctly', () {
      final json = {
        'level': 2,
        'progress': 0.75,
        'current': 38,
        'next_threshold': 50,
      };

      final track = TrackProgress.fromJson(json);

      expect(track.level, 2);
      expect(track.progress, 0.75);
      expect(track.current, 38);
      expect(track.nextThreshold, 50);
    });

    test('fromJson handles null values with defaults', () {
      final track = TrackProgress.fromJson({});

      expect(track.level, 0);
      expect(track.progress, 0.0);
      expect(track.current, 0);
      expect(track.nextThreshold, 0);
    });

    test('levelName returns correct names', () {
      expect(const TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 10).levelName, 'Novice');
      expect(const TrackProgress(level: 1, progress: 0, current: 10, nextThreshold: 50).levelName, 'Bronze');
      expect(const TrackProgress(level: 2, progress: 0, current: 50, nextThreshold: 200).levelName, 'Silver');
      expect(const TrackProgress(level: 3, progress: 1, current: 200, nextThreshold: 200).levelName, 'Gold');
    });

    test('isMaxLevel is true only at level 3', () {
      expect(const TrackProgress(level: 0, progress: 0, current: 0, nextThreshold: 10).isMaxLevel, false);
      expect(const TrackProgress(level: 2, progress: 0.5, current: 50, nextThreshold: 200).isMaxLevel, false);
      expect(const TrackProgress(level: 3, progress: 1, current: 200, nextThreshold: 200).isMaxLevel, true);
    });
  });

  group('StreakInfo', () {
    test('fromJson parses correctly', () {
      final json = {'current': 5, 'longest': 12};
      final streak = StreakInfo.fromJson(json);

      expect(streak.current, 5);
      expect(streak.longest, 12);
    });

    test('hasStreak returns correct value', () {
      expect(const StreakInfo(current: 0, longest: 5).hasStreak, false);
      expect(const StreakInfo(current: 1, longest: 5).hasStreak, true);
    });
  });

  group('GamificationConfig', () {
    test('fromJson parses correctly', () {
      final json = {
        'achievements_style': 'fun',
        'reading_goal_yearly': 24,
        'reading_goal_progress': 12,
      };
      final config = GamificationConfig.fromJson(json);

      expect(config.achievementsStyle, 'fun');
      expect(config.readingGoalYearly, 24);
      expect(config.readingGoalProgress, 12);
    });

    test('goalProgress calculates correctly', () {
      final config = GamificationConfig.fromJson({
        'reading_goal_yearly': 24,
        'reading_goal_progress': 6,
      });
      expect(config.goalProgress, 0.25);
    });

    test('goalProgress clamps to 1.0 when exceeded', () {
      final config = GamificationConfig.fromJson({
        'reading_goal_yearly': 10,
        'reading_goal_progress': 15,
      });
      expect(config.goalProgress, 1.0);
    });

    test('goalProgress handles zero goal', () {
      final config = GamificationConfig.fromJson({
        'reading_goal_yearly': 0,
        'reading_goal_progress': 5,
      });
      expect(config.goalProgress, 0.0);
    });
  });

  group('GamificationStatus', () {
    test('fromJson parses complete response', () {
      final json = {
        'tracks': {
          'collector': {'level': 1, 'progress': 0.75, 'current': 38, 'next_threshold': 50},
          'reader': {'level': 0, 'progress': 0.40, 'current': 8, 'next_threshold': 20},
          'lender': {'level': 0, 'progress': 0.20, 'current': 1, 'next_threshold': 5},
        },
        'streak': {'current': 5, 'longest': 12},
        'recent_achievements': ['collector_bronze', 'first_scan'],
        'config': {
          'achievements_style': 'minimal',
          'reading_goal_yearly': 24,
          'reading_goal_progress': 8,
        },
        'level': 'BiblioGenius',
        'loans_count': 10,
        'edits_count': 38,
        'next_level_progress': 0.45,
        'badge_url': 'assets/badges/bibliogenius.png',
      };

      final status = GamificationStatus.fromJson(json);

      // Tracks
      expect(status.collector.level, 1);
      expect(status.collector.current, 38);
      expect(status.reader.level, 0);
      expect(status.lender.progress, 0.20);

      // Streak
      expect(status.streak.current, 5);
      expect(status.streak.longest, 12);

      // Achievements
      expect(status.recentAchievements, ['collector_bronze', 'first_scan']);

      // Config
      expect(status.config.achievementsStyle, 'minimal');
      expect(status.config.readingGoalYearly, 24);

      // Legacy
      expect(status.level, 'BiblioGenius');
      expect(status.loansCount, 10);
      expect(status.badgeUrl, 'assets/badges/bibliogenius.png');
    });

    test('fromJson handles missing tracks gracefully', () {
      final json = {
        'level': 'Member',
        'loans_count': 0,
        'edits_count': 0,
        'next_level_progress': 0.0,
        'badge_url': 'assets/badges/member.png',
      };

      final status = GamificationStatus.fromJson(json);

      expect(status.collector.level, 0);
      expect(status.reader.level, 0);
      expect(status.lender.level, 0);
      expect(status.streak.current, 0);
      expect(status.recentAchievements, isEmpty);
    });

    test('maxTrackLevel returns highest level', () {
      final status = GamificationStatus(
        collector: const TrackProgress(level: 2, progress: 0.5, current: 50, nextThreshold: 200),
        reader: const TrackProgress(level: 1, progress: 0.3, current: 10, nextThreshold: 20),
        lender: const TrackProgress(level: 0, progress: 0.1, current: 1, nextThreshold: 5),
        streak: const StreakInfo(current: 0, longest: 0),
        recentAchievements: const [],
        config: const GamificationConfig(achievementsStyle: 'minimal', readingGoalYearly: 12, readingGoalProgress: 0),
        level: 'BiblioGenius',
        loansCount: 0,
        editsCount: 0,
        nextLevelProgress: 0.0,
        badgeUrl: '',
      );

      expect(status.maxTrackLevel, 2);
    });

    test('hasAchievements is correct', () {
      expect(GamificationStatus.empty.hasAchievements, false);
      
      final withAchievements = GamificationStatus.fromJson({
        'recent_achievements': ['first_book'],
      });
      expect(withAchievements.hasAchievements, true);
    });

    test('empty provides sensible defaults', () {
      final empty = GamificationStatus.empty;

      expect(empty.level, 'Member');
      expect(empty.collector.level, 0);
      expect(empty.streak.current, 0);
      expect(empty.recentAchievements, isEmpty);
    });
  });
}
