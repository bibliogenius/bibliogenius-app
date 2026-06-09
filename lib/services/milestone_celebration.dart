import 'package:flutter/material.dart';

import '../models/gamification_status.dart';
import '../widgets/badge_unlock_animation.dart';
import '../widgets/gamification_widgets.dart';
import '../widgets/level_up_animation.dart';
import 'ffi_service.dart';
import 'translation_service.dart';

/// One of the four gamification tracks.
enum GamificationTrack { collector, reader, lender, cataloguer }

/// A track that just crossed into a new level ("cap" / palier).
class TrackLevelUp {
  final GamificationTrack track;
  final int newLevel;

  const TrackLevelUp(this.track, this.newLevel);
}

/// Detects gamification milestone crossings and plays the matching celebration,
/// reusing the profile's vocabulary and design:
///
/// * a **track level-up** (Novice -> Platine on Collector / Reader / Lender /
///   Cataloguer) plays [LevelUpAnimation] with the tier name (e.g. "Or");
/// * a **status badge unlock** (Curieux / Initié / Bibliophile / Érudit, derived
///   from the track levels) plays [BadgeUnlockAnimation] with the same SVG badge
///   shown on the profile. The two are complementary and can fire together.
///
/// Track levels are the source of truth computed by the Rust backend
/// (`calculate_track_progress`); we never persist them client-side. To attribute
/// a crossing to a *specific* user action (and avoid re-triggering when a count
/// merely rests on a threshold), callers [snapshot] the levels **before** the
/// action and call [celebrate] **after** it succeeds. Only a strict increase
/// fires an animation.
///
/// Typical use at a mutation site:
/// ```dart
/// final before = await MilestoneCelebration.snapshot();
/// await bookRepo.createBook(...);
/// if (mounted) MilestoneCelebration.celebrate(context, before);
/// ```
class MilestoneCelebration {
  MilestoneCelebration._();

  /// Captures the current per-track levels, or `null` when unavailable
  /// (FFI backend not initialised, e.g. web mode, or the call failed). On
  /// `null` we stay silent rather than risk a false celebration.
  static Future<Map<GamificationTrack, int>?> snapshot() async {
    final ffi = FfiService();
    if (!ffi.isInitialized) return null;
    try {
      final status = await ffi.getGamificationStatus();
      return {
        GamificationTrack.collector: status.collector.level,
        GamificationTrack.reader: status.reader.level,
        GamificationTrack.lender: status.lender.level,
        GamificationTrack.cataloguer: status.cataloguer.level,
      };
    } catch (e) {
      debugPrint('MilestoneCelebration.snapshot failed (non-blocking): $e');
      return null;
    }
  }

  /// Pure: tracks whose level strictly increased from [before] to [after].
  /// Exposed for unit testing.
  static List<TrackLevelUp> diff(
    Map<GamificationTrack, int> before,
    Map<GamificationTrack, int> after,
  ) {
    final ups = <TrackLevelUp>[];
    for (final track in GamificationTrack.values) {
      final from = before[track] ?? 0;
      final to = after[track] ?? 0;
      if (to > from) ups.add(TrackLevelUp(track, to));
    }
    return ups;
  }

  /// Pure: the status-badge index (0..3 -> Curieux/Initié/Bibliophile/Érudit)
  /// implied by a set of track levels. Mirrors the profile's badge logic.
  /// Exposed for unit testing.
  static int statusBadgeIndex(Map<GamificationTrack, int> levels) {
    final values = GamificationTrack.values
        .map((t) => levels[t] ?? 0)
        .toList(growable: false);
    final minLevel = values.reduce((a, b) => a < b ? a : b);
    final maxLevel = values.reduce((a, b) => a > b ? a : b);
    return getStatusBadgeIndex(
      GamificationStatus.statusLevelFor(minLevel: minLevel, maxLevel: maxLevel),
    );
  }

  /// Fetches the post-action levels, diffs against [before], and plays the
  /// level-up animation(s) plus, if the status badge advanced, the badge-unlock
  /// animation.
  ///
  /// No-op when [before] is `null` or nothing changed. Safe to fire-and-forget:
  /// the root overlay and every translated label are captured synchronously
  /// (while [context] is still mounted) before the first `await`, so the
  /// animations survive the caller navigating away.
  static void celebrate(
    BuildContext context,
    Map<GamificationTrack, int>? before,
  ) {
    if (before == null) return;

    // Capture everything that needs a live context up-front (before any await).
    final overlay = Overlay.of(context, rootOverlay: true);
    final trackNames = <GamificationTrack, String>{
      for (final track in GamificationTrack.values)
        track: TranslationService.translate(context, _meta(track).nameKey),
    };
    final tierNames = trackTierNames(context);
    final badgeNames = <String>[
      for (var i = 0; i < 4; i++)
        TranslationService.translate(context, getBadgeInfo(i).translationKey),
    ];
    final badgeSubtitle =
        TranslationService.translate(context, 'new_badge_unlocked');

    () async {
      final after = await snapshot();
      if (after == null) return;

      // Build the ordered list of overlays to play: track level-ups first, then
      // the status badge unlock (the "grand finale") if it advanced.
      final plays = <void Function()>[];
      for (final up in diff(before, after)) {
        final meta = _meta(up.track);
        final label = trackLevelLabel(up.newLevel, tierNames);
        // Accent the celebration with the *tier* colour reached (Bronze/Or/...),
        // while the track stays identified by its icon and name.
        plays.add(() => LevelUpAnimation.showInOverlay(
              overlay,
              newLevel: up.newLevel,
              levelLabel: label,
              trackName: trackNames[up.track]!,
              trackColor: trackTierColor(up.newLevel),
              trackIcon: meta.icon,
            ));
      }

      final badgeBefore = statusBadgeIndex(before);
      final badgeAfter = statusBadgeIndex(after);
      if (badgeAfter > badgeBefore) {
        final info = getBadgeInfo(badgeAfter);
        plays.add(() => BadgeUnlockAnimation.showInOverlay(
              overlay,
              badgeName: badgeNames[badgeAfter],
              badgeAssetPath: info.assetPath,
              badgeColor: info.color,
              subtitle: badgeSubtitle,
            ));
      }

      // Stagger so the full-screen overlays do not stack on top of each other.
      for (var i = 0; i < plays.length; i++) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 4300));
        if (!overlay.mounted) return;
        plays[i]();
      }
    }();
  }

  /// Per-track identity (name key + icon) mirroring the profile screen
  /// (`gamification_widgets.dart`). The celebration colour comes from the tier
  /// reached ([trackTierColor]), not the track, so no colour is stored here.
  static _TrackMeta _meta(GamificationTrack track) {
    switch (track) {
      case GamificationTrack.collector:
        return const _TrackMeta('track_collector', Icons.collections_bookmark);
      case GamificationTrack.reader:
        return const _TrackMeta('track_reader', Icons.menu_book);
      case GamificationTrack.lender:
        return const _TrackMeta('track_lender', Icons.volunteer_activism);
      case GamificationTrack.cataloguer:
        return const _TrackMeta('track_cataloguer', Icons.list_alt);
    }
  }
}

class _TrackMeta {
  final String nameKey;
  final IconData icon;

  const _TrackMeta(this.nameKey, this.icon);
}
