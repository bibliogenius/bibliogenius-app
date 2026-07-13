import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Compact, opaque pill showing a volume's reading-order number (or a dash when
/// unnumbered), optionally tappable to edit it. Shared by the series surfaces
/// (the collection detail list and the book-detail frise) so the number reads
/// identically in both. Uses a solid fill, contrasting border and a soft shadow
/// so it stays legible sitting on top of any cover artwork.
class VolumeBadge extends StatelessWidget {
  final int? volumeNumber;
  final VoidCallback? onTap;
  final double size;

  const VolumeBadge({
    super.key,
    required this.volumeNumber,
    this.onTap,
    this.size = 23,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNumber = volumeNumber != null;
    final label = hasNumber ? '$volumeNumber' : '–';
    final tooltip = hasNumber
        ? '${TranslationService.translate(context, 'series_volume_number')} $volumeNumber'
        : TranslationService.translate(context, 'series_unnumbered');
    final semanticLabel =
        '${TranslationService.translate(context, 'series_edit_volume')}: $label';

    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasNumber
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: hasNumber
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          height: 1,
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(
        label: semanticLabel,
        child: Tooltip(message: tooltip, child: badge),
      );
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: badge,
        ),
      ),
    );
  }
}
