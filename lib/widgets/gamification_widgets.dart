import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/gamification_status.dart';
import '../services/translation_service.dart';

class BadgeInfo {
  final String assetPath;
  final String translationKey;
  final String descriptionKey;
  final Color color;
  final Color secondaryColor;

  BadgeInfo({
    required this.assetPath,
    required this.translationKey,
    required this.descriptionKey,
    required this.color,
    required this.secondaryColor,
  });
}

// Status badges definitions by index (0-3)
BadgeInfo getBadgeInfo(int index) {
  switch (index) {
    case 0:
      return BadgeInfo(
        assetPath: 'assets/images/badges/curieux.svg',
        translationKey: 'level_curieux',
        descriptionKey: 'badge_desc_curieux',
        color: const Color(0xFF4CAF50), // Green
        secondaryColor: const Color(0xFF81C784),
      );
    case 1:
      return BadgeInfo(
        assetPath: 'assets/images/badges/initie.svg',
        translationKey: 'level_initie',
        descriptionKey: 'badge_desc_initie',
        color: const Color(0xFF2196F3), // Blue
        secondaryColor: const Color(0xFF64B5F6),
      );
    case 2:
      return BadgeInfo(
        assetPath: 'assets/images/badges/bibliophile.svg',
        translationKey: 'level_bibliophile',
        descriptionKey: 'badge_desc_bibliophile',
        color: const Color(0xFFFF9800), // Orange
        secondaryColor: const Color(0xFFFFB74D),
      );
    case 3:
    default:
      return BadgeInfo(
        assetPath: 'assets/images/badges/erudit.svg',
        translationKey: 'level_erudit',
        descriptionKey: 'badge_desc_erudit',
        color: const Color(0xFFFFC107), // Gold
        secondaryColor: const Color(0xFFFFD54F),
      );
  }
}

/// Maps the user's calculated status level (based on track levels) to a badge index (0-3).
/// statusLevel logic:
/// - 5+ (requires ALL tracks Gold/Platine) -> 3 (Érudit)
/// - 3+ (requires ALL tracks Bronze+) -> 2 (Bibliophile)
/// - 2+ (requires ONE track Apprenti) -> 1 (Initié)
/// - 0-1 -> 0 (Curieux)
int getStatusBadgeIndex(int statusLevel) {
  if (statusLevel >= 5) return 3; // Érudit
  if (statusLevel >= 3) return 2; // Bibliophile
  if (statusLevel >= 2) return 1; // Initié
  return 0; // Curieux
}

/// Shows a dialog explaining the level thresholds for a gamification track.
void showTrackLevelInfo(
  BuildContext context, {
  required String trackName,
  required TrackProgress track,
  required IconData icon,
  required Color color,
}) {
  // Define thresholds for each track type
  // All tracks now use 6 levels: Novice (25), Apprenti (50), Bronze (100), Argent (250), Or (500), Platine (1000)
  final thresholds = {
    'collector': [25, 50, 100, 250, 500, 1000],
    'reader': [25, 50, 100, 250, 500, 1000],
    'lender': [25, 50, 100, 250, 500, 1000],
    'cataloguer': [25, 50, 100, 250, 500, 1000],
  };

  // Determine track type from name
  // Order matters! "Collectionneur" contains "lect" so we must check for collector first
  String trackType = 'collector';
  final nameLower = trackName.toLowerCase();
  if (nameLower.contains('collect') || nameLower.contains('collec')) {
    trackType = 'collector';
  } else if (nameLower.contains('lect') || nameLower.contains('read')) {
    trackType = 'reader';
  } else if (nameLower.contains('prêt') || nameLower.contains('lend')) {
    trackType = 'lender';
  } else if (nameLower.contains('catal')) {
    trackType = 'cataloguer';
  }

  final levels = thresholds[trackType] ?? [25, 50, 100, 250, 500, 1000];

  // All tracks now use 6 levels with same names
  final levelNames = [
    TranslationService.translate(context, 'level_novice'),
    TranslationService.translate(context, 'level_apprenti'),
    TranslationService.translate(context, 'level_bronze'),
    TranslationService.translate(context, 'level_silver'),
    TranslationService.translate(context, 'level_gold'),
    TranslationService.translate(context, 'level_platine'),
  ];

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              trackName,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(context, 'badge_progress_info'),
            style: Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          // Current progress
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.star, color: color),
                const SizedBox(width: 8),
                Text(
                  '${TranslationService.translate(context, 'current')}: ${track.current}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(context, 'badge_levels_title'),
            style: Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          // Level thresholds
          ...List.generate(levels.length, (i) {
            final threshold = levels[i];
            final isAchieved = track.current >= threshold;
            final isCurrent = track.level == i + 1;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isAchieved ? color : Colors.grey[300],
                    ),
                    child: Icon(
                      isAchieved ? Icons.check : Icons.lock_outline,
                      size: 14,
                      color: isAchieved ? Colors.white : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${levelNames[i]} : $threshold+',
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isAchieved ? Colors.black87 : Colors.grey,
                        decoration: isAchieved ? TextDecoration.none : null,
                      ),
                    ),
                  ),
                  if (isAchieved)
                    Icon(Icons.emoji_events, color: color, size: 18),
                ],
              ),
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            TranslationService.translate(context, 'close'),
            style: TextStyle(color: color),
          ),
        ),
      ],
    ),
  );
}

class BadgeCollectionWidget extends StatelessWidget {
  final int statusLevel;

  const BadgeCollectionWidget({super.key, required this.statusLevel});

  @override
  Widget build(BuildContext context) {
    // Responsive sizing - larger fonts for desktop
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final titleFontSize = isDesktop ? 16.0 : 12.0;
    final badgeLabelFontSize = isDesktop ? 16.0 : 12.0;
    final currentBadgeIndex = getStatusBadgeIndex(statusLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 8.0,
              bottom: 12.0,
            ),
            child: Text(
              TranslationService.translate(
                context,
                'badge_collection',
              ).toUpperCase(),
              style: TextStyle(
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Use 2x2 grid for narrow screens (< 400px)
              if (constraints.maxWidth < 400) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildBadgeItem(
                            context,
                            0,
                            currentBadgeIndex,
                            isDesktop,
                            badgeLabelFontSize,
                          ),
                        ),
                        Expanded(
                          child: _buildBadgeItem(
                            context,
                            1,
                            currentBadgeIndex,
                            isDesktop,
                            badgeLabelFontSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildBadgeItem(
                            context,
                            2,
                            currentBadgeIndex,
                            isDesktop,
                            badgeLabelFontSize,
                          ),
                        ),
                        Expanded(
                          child: _buildBadgeItem(
                            context,
                            3,
                            currentBadgeIndex,
                            isDesktop,
                            badgeLabelFontSize,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              // Use Row for wide screens
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(4, (index) {
                  return Expanded(
                    child: _buildBadgeItem(
                      context,
                      index,
                      currentBadgeIndex,
                      isDesktop,
                      badgeLabelFontSize,
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeItem(
    BuildContext context,
    int index,
    int currentBadgeIndex,
    bool isDesktop,
    double badgeLabelFontSize,
  ) {
    final badgeInfo = getBadgeInfo(index);
    final isUnlocked = currentBadgeIndex >= index;
    // Match TrackProgressWidget standard size (approx 70-80)
    final badgeSize = isDesktop ? 80.0 : 70.0;
    // Icon inside should be smaller relative to the circle
    final iconSize = badgeSize * 0.5;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: badgeSize,
          height: badgeSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ring (Static)
              Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isUnlocked
                        ? badgeInfo.color.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.2),
                    width: 4,
                  ),
                ),
              ),
              // Inner Background
              Container(
                width: badgeSize - 12, // slightly smaller than ring
                height: badgeSize - 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isUnlocked
                      ? badgeInfo.color.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                ),
              ),
              // Badge Icon
              Opacity(
                opacity: isUnlocked ? 1.0 : 0.4,
                child: SvgPicture.asset(
                  badgeInfo.assetPath,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                  colorFilter: isUnlocked
                      ? null
                      : const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                ),
              ),
              // Lock icon for locked badges
              if (!isUnlocked)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(Icons.lock, size: 12, color: Colors.grey[600]),
                  ),
                ),
              // Checkmark for unlocked (optional, similar to track widgets having checkmarks/levels?)
              // Tracks show level numbers. For these static badges, maybe just the visual is enough.
              // Let's add a small checkmark if it's unlocked for extra "completed" feel
              if (isUnlocked)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: badgeInfo.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            TranslationService.translate(
              context,
              badgeInfo.translationKey,
            ).split(' ').last,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: badgeLabelFontSize,
              fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
              color: isUnlocked ? badgeInfo.color : Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            TranslationService.translate(
              context,
              badgeInfo.descriptionKey,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop ? 12.0 : 10.0,
              color: isUnlocked
                  ? Theme.of(context).textTheme.bodySmall?.color
                  : Colors.grey,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class CurrentBadgeWidget extends StatefulWidget {
  final int statusLevel;

  const CurrentBadgeWidget({super.key, required this.statusLevel});

  @override
  State<CurrentBadgeWidget> createState() => _CurrentBadgeWidgetState();
}

class _CurrentBadgeWidgetState extends State<CurrentBadgeWidget>
    with SingleTickerProviderStateMixin {
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
    final currentBadgeIndex = getStatusBadgeIndex(widget.statusLevel);
    // Prestige affects animation (but max logic is handled by statusLevel > 5 check if needed,
    // though statusLevel is capped at 5 in model? No, model cap is 5. 5 is Érudit.)
    // Let's assume Prestige effect is for the top tier.
    final badgeInfo = getBadgeInfo(currentBadgeIndex);
    final isPrestige = widget.statusLevel >= 5;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            badgeInfo.color.withValues(alpha: 0.1),
            badgeInfo.secondaryColor.withValues(alpha: 0.05),
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
            padding: const EdgeInsets.symmetric(
              vertical: 32.0,
              horizontal: 24.0,
            ),
            child: Column(
              children: [
                // Level Name Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: badgeInfo.color.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    isPrestige
                        ? '${TranslationService.translate(context, badgeInfo.translationKey)} ${widget.statusLevel}'
                        : TranslationService.translate(
                            context,
                            badgeInfo.translationKey,
                          ),
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
                  scale: isPrestige
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: badgeInfo.color.withValues(
                            alpha: isPrestige ? 0.6 : 0.4,
                          ),
                          blurRadius: isPrestige ? 30 : 20,
                          spreadRadius: isPrestige ? 5 : 0,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: SvgPicture.asset(
                      badgeInfo.assetPath,
                      width: 140,
                      height: 140,
                      fit: BoxFit.contain,
                      placeholderBuilder: (context) => Container(
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
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Current Level Label
                Text(
                  TranslationService.translate(
                    context,
                    'your_current_level',
                  ).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
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
    // Responsive sizing - larger fonts for desktop
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final labelStyle = isDesktop
        ? Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)
        : Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500);
    final progressStyle = isDesktop
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)
        : Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey);
    final levelFontSize = isDesktop ? 12.0 : 10.0;

    return GestureDetector(
      onTap: () => showTrackLevelInfo(
        context,
        trackName: trackName,
        track: track,
        icon: icon,
        color: color,
      ),
      child: Column(
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
                  child: Icon(icon, color: color, size: size * 0.35),
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
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: levelFontSize,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(trackName, style: labelStyle),
          // Show progress intelligently: if current >= nextThreshold, show level completed
          Text(
            track.isMaxLevel
                ? '${track.current} ✓'
                : track.current >= track.nextThreshold
                ? '${track.current}/${track.nextThreshold} ✓'
                : '${track.current}/${track.nextThreshold}',
            style: progressStyle,
          ),
        ],
      ),
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

  const TracksProgressRow({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use Row for wide screens (>400px), 2x2 grid for narrow ones
        if (constraints.maxWidth > 400) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TrackProgressWidget(
                  track: status.collector,
                  trackName: TranslationService.translate(
                    context,
                    'track_collector',
                  ),
                  icon: Icons.collections_bookmark,
                  color: Colors.blue,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.reader,
                  trackName: TranslationService.translate(
                    context,
                    'track_reader',
                  ),
                  icon: Icons.menu_book,
                  color: Colors.green,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.lender,
                  trackName: TranslationService.translate(
                    context,
                    'track_lender',
                  ),
                  icon: Icons.volunteer_activism,
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: TrackProgressWidget(
                  track: status.cataloguer,
                  trackName: TranslationService.translate(
                    context,
                    'track_cataloguer',
                  ),
                  icon: Icons.list_alt,
                  color: Colors.purple,
                ),
              ),
            ],
          );
        } else {
          // 2x2 grid for narrow screens - avoids 3+1 awkward layout
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TrackProgressWidget(
                    track: status.collector,
                    trackName: TranslationService.translate(
                      context,
                      'track_collector',
                    ),
                    icon: Icons.library_books,
                    color: Colors.blue,
                  ),
                  TrackProgressWidget(
                    track: status.reader,
                    trackName: TranslationService.translate(
                      context,
                      'track_reader',
                    ),
                    icon: Icons.menu_book,
                    color: Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TrackProgressWidget(
                    track: status.lender,
                    trackName: TranslationService.translate(
                      context,
                      'track_lender',
                    ),
                    icon: Icons.handshake,
                    color: Colors.orange,
                  ),
                  TrackProgressWidget(
                    track: status.cataloguer,
                    trackName: TranslationService.translate(
                      context,
                      'track_cataloguer',
                    ),
                    icon: Icons.sort,
                    color: Colors.purple,
                  ),
                ],
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

  const StreakWidget({super.key, required this.streak});

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
          const Icon(
            Icons.local_fire_department,
            color: Colors.orange,
            size: 20,
          ),
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
class GamificationSummaryCard extends StatefulWidget {
  final GamificationStatus status;
  final VoidCallback? onTap;

  const GamificationSummaryCard({super.key, required this.status, this.onTap});

  @override
  State<GamificationSummaryCard> createState() =>
      _GamificationSummaryCardState();
}

class _GamificationSummaryCardState extends State<GamificationSummaryCard> {
  bool _showHelp = false;

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
              ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
              : [Colors.white, const Color(0xFFF5F7FA)],
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
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title, info button and streak
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
                            TranslationService.translate(
                              context,
                              'your_progress',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _showHelp = !_showHelp),
                            child: Icon(
                              _showHelp ? Icons.close : Icons.help_outline,
                              size: 20,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      StreakWidget(streak: widget.status.streak),
                    ],
                  ),

                  // Help panel (expandable)
                  if (_showHelp) ...[
                    const SizedBox(height: 16),
                    _buildHelpPanel(context, isDark),
                  ],

                  // Dynamic progress hint
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                    child: Text(
                      _getProgressHint(context),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                  // Badge Collection
                  BadgeCollectionWidget(statusLevel: widget.status.statusLevel),

                  const SizedBox(height: 16),
                  const Divider(height: 1, indent: 24, endIndent: 24),
                  const SizedBox(height: 24),

                  // Tracks with enhanced layout
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: TracksProgressRow(status: widget.status),
                  ),

                  // Reading goal progress (if enabled)
                  if (widget.status.config.readingGoalYearly > 0) ...[
                    const SizedBox(height: 20),
                    _buildReadingGoalSection(context),
                  ],

                  // Achievements section
                  if (widget.status.hasAchievements) ...[
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
                                TranslationService.translate(
                                  context,
                                  'recent_achievements',
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: widget.status.recentAchievements
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

  String _getProgressHint(BuildContext context) {
    final badgeIndex = getStatusBadgeIndex(widget.status.statusLevel);
    switch (badgeIndex) {
      case 0:
        return TranslationService.translate(context, 'progress_hint_curieux');
      case 1:
        return TranslationService.translate(context, 'progress_hint_initie');
      case 2:
        return TranslationService.translate(
          context,
          'progress_hint_bibliophile',
        );
      case 3:
        return TranslationService.translate(context, 'progress_hint_erudit');
      default:
        return TranslationService.translate(context, 'progress_hint_curieux');
    }
  }

  Widget _buildHelpPanel(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.blue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(context, 'gamification_how_it_works'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.blue[800],
            ),
          ),
          const SizedBox(height: 12),

          // Badges explanation
          _buildHelpItem(
            context,
            Icons.collections_bookmark,
            TranslationService.translate(context, 'track_collector'),
            TranslationService.translate(
              context,
              'gamification_collector_desc',
            ),
            Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildHelpItem(
            context,
            Icons.menu_book,
            TranslationService.translate(context, 'track_reader'),
            TranslationService.translate(context, 'gamification_reader_desc'),
            Colors.green,
          ),
          const SizedBox(height: 8),
          _buildHelpItem(
            context,
            Icons.volunteer_activism,
            TranslationService.translate(context, 'track_lender'),
            TranslationService.translate(context, 'gamification_lender_desc'),
            Colors.orange,
          ),
          const SizedBox(height: 8),
          _buildHelpItem(
            context,
            Icons.list_alt,
            TranslationService.translate(context, 'track_cataloguer'),
            TranslationService.translate(
              context,
              'gamification_cataloguer_desc',
            ),
            Colors.purple,
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Status badges explanation
          Text(
            TranslationService.translate(context, 'gamification_status_title'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'gamification_status_desc'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Levels explanation
          Text(
            TranslationService.translate(context, 'gamification_levels_title'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'gamification_levels_desc'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),

          const SizedBox(height: 12),

          // Streak explanation
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                size: 18,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslationService.translate(
                    context,
                    'gamification_streak_desc',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadingGoalSection(BuildContext context) {
    final progress = widget.status.config.goalProgress;
    final current = widget.status.config.readingGoalProgress;
    final goal = widget.status.config.readingGoalYearly;

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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
          Icon(_getAchievementIcon(id), size: 14, color: Colors.amber[700]),
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
      return id
          .replaceAll('_', ' ')
          .split(' ')
          .map(
            (word) => word.isNotEmpty
                ? '${word[0].toUpperCase()}${word.substring(1)}'
                : '',
          )
          .join(' ');
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
