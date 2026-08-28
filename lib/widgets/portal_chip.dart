import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/translation_service.dart';

/// Pill-shaped outbound link: hugs its label (no full-width row whose
/// action icon drifts to the far card edge on desktop) and wraps on
/// narrow screens. The trailing arrow says "leaves the app" visually;
/// the tooltip says it to screen readers and on long-press.
class PortalChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Uri uri;

  const PortalChip({
    super.key,
    required this.icon,
    required this.label,
    required this.uri,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      tooltip: TranslationService.translate(context, 'opens_external_site'),
      avatar: Icon(icon, size: 16, color: theme.colorScheme.primary),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 4),
          Icon(
            Icons.open_in_new,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onPressed: () => launchUrl(uri, mode: LaunchMode.inAppBrowserView),
    );
  }
}
