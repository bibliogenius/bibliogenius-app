import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// The concept a screen is not about, with the rule that tells shelves and
/// collections apart.
///
/// Shown under the empty state of the shelves tab (about collections) and of
/// the collections tab (about shelves), so the reader meets both sentences
/// and the same rule wherever they start.
class ShelfOrCollectionNote extends StatelessWidget {
  /// `collection_concept` or `shelf_concept`.
  final String conceptKey;

  const ShelfOrCollectionNote({super.key, required this.conceptKey});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.45,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        // Themes built with ColorScheme.light() leave the container color at
        // `surface`, the page color: the border keeps the note visible there.
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TranslationService.translate(context, conceptKey), style: body),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'shelf_or_collection_rule'),
            style: body?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
