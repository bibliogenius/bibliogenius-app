import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Narrows the wishlist to one reader's wishes.
///
/// Shown only when the wishes name at least one reader: a library without
/// readers, or with anonymous wishes only, keeps its wishlist as it was.
class WisherFilterChips extends StatelessWidget {
  final List<String> names;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const WisherFilterChips({
    super.key,
    required this.names,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          FilterChip(
            label: Text(TranslationService.translate(context, 'filter_all')),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final name in names) ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.favorite, size: 16),
              label: Text(name),
              selected: selected == name,
              onSelected: (on) => onChanged(on ? name : null),
            ),
          ],
        ],
      ),
    );
  }
}
