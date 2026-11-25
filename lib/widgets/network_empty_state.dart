import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';

/// Shared layout of the Network screen's empty states: an icon in a tinted
/// circle, a title, a hint and an optional action.
class NetworkEmptyStateContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String titleKey;
  final String hintKey;

  /// A second paragraph under the hint, when one platform needs it.
  final String? extraHintKey;
  final Widget? actionWidget;

  const NetworkEmptyStateContent({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.titleKey,
    required this.hintKey,
    this.extraHintKey,
    this.actionWidget,
  });

  @override
  Widget build(BuildContext context) {
    final hintStyle = TextStyle(
      fontSize: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: iconColor),
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, titleKey),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, hintKey),
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
            if (extraHintKey != null) ...[
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(context, extraHintKey!),
                textAlign: TextAlign.center,
                style: hintStyle,
              ),
            ],
            if (actionWidget != null) ...[
              const SizedBox(height: 32),
              actionWidget!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state of the "Nearby" filter.
///
/// Local discovery (mDNS) is off on a fresh install, and since ADR-073 the
/// local network is the only way to pair without a hub registration. Saying
/// "no nearby libraries" while this device is not even listening sends the
/// reader looking for a problem that is not there, so when discovery is off
/// this state says so and turns it on in one tap.
class NearbyEmptyState extends StatelessWidget {
  const NearbyEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final discoveryOn = context.select<ThemeProvider, bool>(
      (theme) => theme.networkEnabled,
    );
    if (discoveryOn) {
      return const NetworkEmptyStateContent(
        key: Key('networkEmptyNearby'),
        icon: Icons.wifi_off,
        iconColor: Colors.grey,
        titleKey: 'no_nearby_peers',
        hintKey: 'no_nearby_peers_hint',
      );
    }
    // Turning discovery on starts Bonjour, which is what makes iOS ask for
    // local network access: the reader should know why the system asks.
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    return NetworkEmptyStateContent(
      key: const Key('networkEmptyNearbyDiscoveryOff'),
      icon: Icons.wifi_find,
      iconColor: Colors.blueGrey,
      titleKey: 'nearby_discovery_off_title',
      hintKey: 'nearby_discovery_off_hint',
      extraHintKey: isIos ? 'nearby_discovery_off_ios_hint' : null,
      actionWidget: ElevatedButton.icon(
        key: const Key('enableNearbyDiscoveryBtn'),
        onPressed: () => context.read<ThemeProvider>().setNetworkEnabled(true),
        icon: const Icon(Icons.wifi),
        label: Text(
          TranslationService.translate(context, 'nearby_discovery_enable_btn'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
