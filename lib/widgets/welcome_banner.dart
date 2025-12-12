import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../models/gamification_status.dart';

/// A premium gradient banner widget that can be displayed on any page.
/// 
/// Shows a greeting with the library/user name, and optionally displays
/// a streak badge if a GamificationStatus is provided.
class WelcomeBanner extends StatelessWidget {
  final String? libraryName;
  final String? userName;
  final GamificationStatus? gamificationStatus;
  final bool showGreeting;
  final bool compact;

  const WelcomeBanner({
    super.key,
    this.libraryName,
    this.userName,
    this.gamificationStatus,
    this.showGreeting = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = libraryName ?? userName ?? 'BiblioGenius';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667eea).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: compact ? 24 : 28,
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          // Name and streak
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: compact ? 18 : 24,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (gamificationStatus != null && gamificationStatus!.streak.hasStreak)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${gamificationStatus!.streak.current} ${TranslationService.translate(context, 'days')}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
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

/// A compact version of the banner for secondary pages.
class CompactBanner extends StatelessWidget {
  final String libraryName;
  final String? pageTitle;

  const CompactBanner({
    super.key,
    required this.libraryName,
    this.pageTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667eea).withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.menu_book, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  libraryName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (pageTitle != null)
                  Text(
                    pageTitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
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
