// Card for one library of the public directory, with its follow action.
//
// Lives in widgets/ rather than inside network_screen.dart so the screen file
// stays a composition of sections, per the file-size rule in
// .agents/instructions/flutter-frontend.md.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/hub_directory.dart';
import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'hub_location_label.dart';

/// Card for a hub library profile in the Discover tab.
class DiscoverCard extends StatelessWidget {
  final HubProfile profile;

  const DiscoverCard({super.key, required this.profile});

  bool _isOwnLibrary(HubDirectoryProvider provider) =>
      provider.config?.nodeId == profile.nodeId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HubDirectoryProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = profile.displayName;
    final bookCount = profile.bookCount;
    final isOwn = _isOwnLibrary(provider);
    // True when this library has sent us a pending follow request. Surfaced
    // as a small chip inside the card so the user can spot from Discover
    // that the badge-count on My Network maps to this specific library.
    final hasIncomingRequest =
        !isOwn && provider.hasIncomingFollowRequestFrom(profile.nodeId);

    return Semantics(
      button: true,
      label:
          '$name, $bookCount ${TranslationService.translate(context, 'directory_books')}'
          '${isOwn ? ', ${TranslationService.translate(context, 'directory_your_library')}' : ''}'
          '${hasIncomingRequest ? ', ${TranslationService.translate(context, 'directory_wants_to_follow_you')}' : ''}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
              : cs.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          border: Border.all(
            color: isOwn
                ? cs.tertiary.withValues(alpha: 0.3)
                : cs.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          onTap: () =>
              context.push('/directory/${Uri.encodeComponent(profile.nodeId)}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: avatar + name + badge + action.
                // Top-aligned: the name may wrap to a second line, and the
                // action chip must stay level with the first one.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gradient avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: isOwn
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.tertiary,
                                  cs.tertiary.withValues(alpha: 0.7),
                                ],
                              )
                            : AppDesign.refinedSuccessGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  // Names share the line with the action chip,
                                  // which leaves roughly 150 of 360 logical
                                  // pixels on a phone. Since they are generated
                                  // from the device name, one line cut exactly
                                  // the part that tells two libraries apart.
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isOwn) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.tertiary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    TranslationService.translate(
                                      context,
                                      'directory_your_library',
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: cs.tertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          // Meta row: book count + location
                          Row(
                            children: [
                              Icon(
                                Icons.auto_stories,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$bookCount',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (profile.locationCountry != null &&
                                  profile.locationCountry!.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                // Tap on the location chip filters the
                                // directory to that exact country/city
                                // (ADR-035 Phase 2). Discoverable shortcut
                                // alongside the explicit filter button.
                                // Wrapped in Semantics so a screen reader
                                // user knows the chip is tappable (RGAA A1).
                                // Flexible: city names run long ("Paris 20
                                // Ménilmontant") and the meta row has no room
                                // to spare next to the action chip.
                                Flexible(
                                  child: Semantics(
                                    button: true,
                                    label: TranslationService.translate(
                                      context,
                                      'directory_filter_by_location_a11y',
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () {
                                        context
                                            .read<HubDirectoryProvider>()
                                            .loadDirectory(
                                              country: profile.locationCountry,
                                              cityId:
                                                  profile.locationCityId ?? 0,
                                            );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 1,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.location_on_outlined,
                                              size: 14,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 2),
                                            Flexible(
                                              child: HubLocationLabel(
                                                country:
                                                    profile.locationCountry,
                                                cityId: profile.locationCityId,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (profile.requiresApproval) ...[
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Follow action or chevron
                    if (!isOwn) ...[
                      const SizedBox(width: 8),
                      _buildFollowAction(context, provider, cs, isDark),
                    ] else ...[
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                // Incoming follow request marker: this library is waiting for
                // our approval. Placed above the description so the user sees
                // the request context before any library-provided blurb.
                if (hasIncomingRequest) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add_alt_1,
                          size: 13,
                          color: cs.onSecondaryContainer,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'directory_wants_to_follow_you',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Description
                if (profile.description != null &&
                    profile.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowAction(
    BuildContext context,
    HubDirectoryProvider provider,
    ColorScheme cs,
    bool isDark,
  ) {
    final status = provider.followStatusFor(profile.nodeId);

    if (provider.isBusy(profile.nodeId)) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // Already following: outlined chip style
    if (status == 'active') {
      return _FollowChip(
        label: TranslationService.translate(context, 'directory_following'),
        filled: true,
        color: cs.primary,
        isDark: isDark,
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                TranslationService.translate(ctx, 'directory_unfollow_title'),
              ),
              content: Text(
                TranslationService.translate(ctx, 'directory_unfollow_confirm'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(TranslationService.translate(ctx, 'cancel')),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    TranslationService.translate(ctx, 'directory_unfollow'),
                  ),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await provider.unfollow(profile.nodeId);
          }
        },
      );
    }

    // Pending: muted chip
    if (status == 'pending') {
      return _FollowChip(
        label: TranslationService.translate(context, 'directory_pending'),
        filled: false,
        color: cs.onSurfaceVariant,
        isDark: isDark,
      );
    }

    // Not following: prominent action chip
    final label = profile.requiresApproval
        ? TranslationService.translate(context, 'directory_request')
        : TranslationService.translate(context, 'directory_follow');
    return _FollowChip(
      label: label,
      filled: true,
      color: const Color(0xFF3A7186),
      isDark: isDark,
      onPressed: () async {
        final ok = await provider.follow(profile.nodeId);
        if (!context.mounted) return;
        if (!ok || provider.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'directory_follow_error'),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        // Success: confirm to the user. Without this, a follow that
        // requires approval silently switches the chip to "awaiting" -
        // some users perceive it as a missed tap and retry.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                profile.requiresApproval
                    ? 'directory_follow_request_sent'
                    : 'directory_follow_success',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}

/// Styled chip button for follow actions in the directory.
class _FollowChip extends StatelessWidget {
  final String label;
  final bool filled;
  final Color color;
  final bool isDark;
  final VoidCallback? onPressed;

  const _FollowChip({
    required this.label,
    required this.filled,
    required this.color,
    required this.isDark,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: filled
                ? color.withValues(alpha: isDark ? 0.25 : 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: filled ? 0.4 : 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled
                  ? (isDark ? color.withValues(alpha: 0.9) : color)
                  : color.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
