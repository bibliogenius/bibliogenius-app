import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/services/milestone_celebration.dart';
import 'package:bibliogenius/widgets/gamification_widgets.dart';

void main() {
  group('MilestoneCelebration.diff', () {
    Map<GamificationTrack, int> levels({
      int collector = 0,
      int reader = 0,
      int lender = 0,
      int cataloguer = 0,
    }) => {
      GamificationTrack.collector: collector,
      GamificationTrack.reader: reader,
      GamificationTrack.lender: lender,
      GamificationTrack.cataloguer: cataloguer,
    };

    test('no change yields no crossings', () {
      final before = levels(collector: 4);
      final after = levels(collector: 4);
      expect(MilestoneCelebration.diff(before, after), isEmpty);
    });

    test('a track resting on a threshold does not re-trigger', () {
      // Collector sits at level 5 (e.g. exactly 500 books) and another action
      // (marking a book read) happens. Collector must NOT celebrate again.
      final before = levels(collector: 5, reader: 2);
      final after = levels(collector: 5, reader: 3);
      final ups = MilestoneCelebration.diff(before, after);
      expect(ups, hasLength(1));
      expect(ups.single.track, GamificationTrack.reader);
      expect(ups.single.newLevel, 3);
    });

    test('crossing the Collector Or cap (level 4 -> 5) is detected', () {
      final before = levels(collector: 4);
      final after = levels(collector: 5);
      final ups = MilestoneCelebration.diff(before, after);
      expect(ups, hasLength(1));
      expect(ups.single.track, GamificationTrack.collector);
      expect(ups.single.newLevel, 5);
    });

    test('two tracks crossing at once both reported', () {
      final before = levels(collector: 2, cataloguer: 2);
      final after = levels(collector: 3, cataloguer: 3);
      final ups = MilestoneCelebration.diff(before, after);
      expect(ups.map((u) => u.track).toSet(), {
        GamificationTrack.collector,
        GamificationTrack.cataloguer,
      });
      expect(ups.every((u) => u.newLevel == 3), isTrue);
    });

    test('a level decrease (e.g. after a deletion) is never celebrated', () {
      final before = levels(collector: 5);
      final after = levels(collector: 4);
      expect(MilestoneCelebration.diff(before, after), isEmpty);
    });

    test('missing keys default to level 0', () {
      final ups = MilestoneCelebration.diff(
        const {},
        {GamificationTrack.reader: 1},
      );
      expect(ups, hasLength(1));
      expect(ups.single.track, GamificationTrack.reader);
    });
  });

  group('MilestoneCelebration.statusBadgeIndex', () {
    Map<GamificationTrack, int> levels(int c, int r, int l, int ca) => {
      GamificationTrack.collector: c,
      GamificationTrack.reader: r,
      GamificationTrack.lender: l,
      GamificationTrack.cataloguer: ca,
    };

    test('all tracks at 0 -> Curieux (0)', () {
      expect(MilestoneCelebration.statusBadgeIndex(levels(0, 0, 0, 0)), 0);
    });

    test('one track at 2 -> Initié (1)', () {
      expect(MilestoneCelebration.statusBadgeIndex(levels(2, 0, 0, 0)), 1);
    });

    test('all tracks at 3 -> Bibliophile (2)', () {
      expect(MilestoneCelebration.statusBadgeIndex(levels(3, 3, 3, 3)), 2);
    });

    test('all tracks at 5 -> Érudit (3)', () {
      expect(MilestoneCelebration.statusBadgeIndex(levels(5, 5, 5, 5)), 3);
    });

    test('Érudit requires the WORST track to reach 5', () {
      // Three tracks at Or but one still at Argent: not Érudit yet.
      final before = levels(5, 5, 5, 4);
      final after = levels(5, 5, 5, 5);
      expect(MilestoneCelebration.statusBadgeIndex(before), 2); // Bibliophile
      expect(MilestoneCelebration.statusBadgeIndex(after), 3); // Érudit
    });
  });

  group('trackLevelLabel', () {
    const tiers = ['Novice', 'Apprenti', 'Bronze', 'Argent', 'Or', 'Platine'];

    test('level 5 is the Or tier (500 books)', () {
      expect(trackLevelLabel(5, tiers), 'Or');
    });

    test('level 6 is Platine', () {
      expect(trackLevelLabel(6, tiers), 'Platine');
    });

    test('prestige levels read as "Platine N"', () {
      expect(trackLevelLabel(7, tiers), 'Platine 1');
      expect(trackLevelLabel(8, tiers), 'Platine 2');
    });

    test('level 1 is Novice; level 0 falls back to the first tier', () {
      expect(trackLevelLabel(1, tiers), 'Novice');
      expect(trackLevelLabel(0, tiers), 'Novice');
    });
  });

  group('trackTierColor', () {
    test('each tier 1..6 has a distinct accent colour', () {
      final colors = [for (var l = 1; l <= 6; l++) trackTierColor(l)];
      expect(colors.toSet(), hasLength(6));
    });

    test('the Or tier (level 5) is gold-toned', () {
      expect(trackTierColor(5), const Color(0xFFE0A516));
    });

    test('prestige (7+) reuses the Platine accent', () {
      expect(trackTierColor(7), trackTierColor(6));
    });
  });
}
