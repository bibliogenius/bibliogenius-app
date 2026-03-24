import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/flash_message_provider.dart';
import '../services/translation_service.dart';

// -- Shared flash card styling --

const _lightBg = Color(0xFFE8F6F5);
const _lightBorder = Color(0xFFB2DFDB);
const _darkBg = Color(0xFF162A30);
const _darkBorder = Color(0xFF1E4A52);

Color _flashBg(bool isDark) => isDark ? _darkBg : _lightBg;
Color _flashBorder(bool isDark) => isDark ? _darkBorder : _lightBorder;

BoxDecoration _flashCardDecoration(ColorScheme colorScheme, bool isDark, {double bgAlpha = 1.0}) {
  final bg = _flashBg(isDark);
  return BoxDecoration(
    color: bgAlpha < 1.0 ? bg.withValues(alpha: bgAlpha) : bg,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _flashBorder(isDark)),
    boxShadow: bgAlpha >= 1.0
        ? [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : null,
  );
}

Widget _flashIconBadge(ColorScheme colorScheme, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: colorScheme.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 16, color: colorScheme.primary),
  );
}

Widget _flashCloseButton(BuildContext context, VoidCallback onPressed) {
  final colorScheme = Theme.of(context).colorScheme;
  return SizedBox(
    width: 28,
    height: 28,
    child: IconButton(
      icon: Icon(
        Icons.close_rounded,
        size: 14,
        color: colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      tooltip: TranslationService.translate(context, 'flash_dismiss_tooltip'),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
  );
}

/// Displays 0-N compact flash message bars above the main content.
/// Static flashes (condition-based) are shown first, followed by
/// ephemeral peer connection flashes (max 3, newest first, with overflow popup).
class FlashMessageBar extends StatelessWidget {
  /// When true, adds top safe area padding (for mobile, where there is no
  /// navigation rail and flashes render at the very top of the screen).
  final bool applyTopSafeArea;

  const FlashMessageBar({super.key, this.applyTopSafeArea = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FlashMessageProvider>();
    final currentRoute = GoRouterState.of(context).uri.path;
    final staticFlashes = provider.getVisibleFlashes(context, currentRoute);
    final ephemeralFlashes = provider.visibleEphemeralFlashes;
    final hasOverflow = provider.hasEphemeralOverflow;

    if (staticFlashes.isEmpty && ephemeralFlashes.isEmpty) {
      return const SizedBox.shrink();
    }

    final topPadding =
        applyTopSafeArea ? MediaQuery.of(context).padding.top : 0.0;

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...staticFlashes.map((def) => _FlashBar(definition: def)),
          ...ephemeralFlashes.map((f) => _EphemeralPeerFlashBar(flash: f)),
          if (hasOverflow)
            _EphemeralSeeMoreRow(count: provider.ephemeralOverflowCount),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FlashBar extends StatelessWidget {
  final FlashMessageDefinition definition;

  const _FlashBar({required this.definition});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconData = definition.icon ?? Icons.info_outline;

    void dismiss() {
      context.read<FlashMessageProvider>().dismiss(definition.key);
    }

    final Widget content;

    if (definition.contentBuilder != null) {
      content = definition.contentBuilder!(context, dismiss);
    } else {
      content = Row(
        children: [
          Expanded(
            child: Text(
              TranslationService.translate(context, definition.textKey),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          if (definition.actionTextKey != null &&
              definition.actionRoute != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => context.go(definition.actionRoute!),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                TranslationService.translate(
                  context,
                  definition.actionTextKey!,
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      );
    }

    final Widget inner;
    if (definition.fullWidthContent) {
      // Close button floats top-right; content gets full width.
      inner = Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: content,
          ),
          Positioned(
            top: -4,
            right: -2,
            child: _flashCloseButton(context, dismiss),
          ),
        ],
      );
    } else {
      inner = Row(
        children: [
          _flashIconBadge(colorScheme, iconData),
          const SizedBox(width: 12),
          Expanded(child: content),
          const SizedBox(width: 4),
          _flashCloseButton(context, dismiss),
        ],
      );
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          definition.fullWidthContent ? 14 : 8,
          12,
        ),
        decoration: _flashCardDecoration(colorScheme, isDark),
        child: inner,
      ),
    );
  }
}

/// Compact bar for a single ephemeral peer connection flash.
/// Shows different text and action for pending vs accepted connections.
class _EphemeralPeerFlashBar extends StatelessWidget {
  final EphemeralPeerFlash flash;

  const _EphemeralPeerFlashBar({required this.flash});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textKey = flash.isPending
        ? 'flash_peer_pending'
        : 'flash_peer_connected';
    final actionKey = flash.isPending
        ? 'flash_peer_review'
        : 'flash_peer_browse';

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: _flashCardDecoration(colorScheme, isDark),
        child: Row(
          children: [
            _flashIconBadge(
              colorScheme,
              flash.isPending ? Icons.person_add : Icons.people,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${TranslationService.translate(context, textKey)} ${flash.peerName}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                if (flash.isPending) {
                  context.push('/requests');
                } else {
                  context.push(
                    '/peers/${flash.peerId}/books',
                    extra: {
                      'id': flash.peerId,
                      'name': flash.peerName,
                      'url': flash.peerUrl ?? '',
                      'hasRelayCredentials': flash.hasRelayCredentials,
                      'nodeId': flash.nodeId ?? '',
                    },
                  );
                }
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                TranslationService.translate(context, actionKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
            _flashCloseButton(
              context,
              () => context
                  .read<FlashMessageProvider>()
                  .dismissEphemeral(flash.peerId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim "see more" row shown when ephemeral flashes exceed the visible limit.
class _EphemeralSeeMoreRow extends StatelessWidget {
  final int count;

  const _EphemeralSeeMoreRow({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: TranslationService.translate(
        context,
        'flash_peer_see_more_semantic',
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        decoration: _flashCardDecoration(colorScheme, isDark, bgAlpha: 0.7),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAllDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              '+ $count ${TranslationService.translate(context, 'flash_peer_see_more')}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  void _showAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _PeerConnectionsDialog(parentContext: context),
    );
  }
}

/// Scrollable dialog listing all ephemeral peer connection flashes.
class _PeerConnectionsDialog extends StatelessWidget {
  final BuildContext parentContext;

  const _PeerConnectionsDialog({required this.parentContext});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Semantics(
        header: true,
        child: Text(
          TranslationService.translate(context, 'flash_peer_dialog_title'),
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Consumer<FlashMessageProvider>(
          builder: (ctx, provider, _) {
            final flashes = provider.allEphemeralFlashes;
            if (flashes.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox.shrink(),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: flashes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final flash = flashes[i];
                final actionKey = flash.isPending
                    ? 'flash_peer_review'
                    : 'flash_peer_browse';
                return ListTile(
                  leading: Icon(
                    flash.isPending ? Icons.person_add : Icons.people,
                  ),
                  title: Text(
                    flash.peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: flash.isPending
                      ? Text(
                          TranslationService.translate(
                            ctx,
                            'flash_peer_pending_hint',
                          ),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          if (flash.isPending) {
                            parentContext.push('/requests');
                          } else {
                            parentContext.push(
                              '/peers/${flash.peerId}/books',
                              extra: {
                                'id': flash.peerId,
                                'name': flash.peerName,
                                'url': flash.peerUrl ?? '',
                                'hasRelayCredentials':
                                    flash.hasRelayCredentials,
                                'nodeId': flash.nodeId ?? '',
                              },
                            );
                          }
                        },
                        child: Text(
                          TranslationService.translate(ctx, actionKey),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: TranslationService.translate(
                          ctx,
                          'flash_dismiss_tooltip',
                        ),
                        onPressed: () {
                          provider.dismissEphemeral(flash.peerId);
                          if (provider.allEphemeralFlashes.isEmpty) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.read<FlashMessageProvider>().dismissAllEphemeral();
            Navigator.of(context).pop();
          },
          child: Text(
            TranslationService.translate(context, 'flash_peer_dismiss_all'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            TranslationService.translate(context, 'close'),
          ),
        ),
      ],
    );
  }
}
