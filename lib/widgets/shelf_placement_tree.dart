import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';
import 'shelf_tree_rows.dart';

/// The shelf tree in placement mode: a tap on a row picks that shelf as a
/// parent, the footer link picks the first level.
///
/// Built to create a shelf at a chosen place ("Create “Night” in…"), and
/// meant to serve moving a shelf as well: [disabledBranchRootId] greys out
/// that shelf and its whole branch, so a shelf can never be placed under
/// itself.
class ShelfPlacementTree extends StatefulWidget {
  final List<Tag> allTags;
  final String title;
  final String? subtitle;

  /// Text of the footer link that places at the first level.
  final String firstLevelLabel;

  /// Root of a branch shown but not tappable, or null.
  final String? disabledBranchRootId;

  /// The chosen parent, null for the first level.
  final ValueChanged<Tag?> onPlace;

  /// Shows a back button in the header when set.
  final VoidCallback? onBack;

  const ShelfPlacementTree({
    super.key,
    required this.allTags,
    required this.title,
    this.subtitle,
    required this.firstLevelLabel,
    this.disabledBranchRootId,
    required this.onPlace,
    this.onBack,
  });

  @override
  State<ShelfPlacementTree> createState() => _ShelfPlacementTreeState();
}

class _ShelfPlacementTreeState extends State<ShelfPlacementTree> {
  final _filterController = TextEditingController();
  Timer? _debounce;
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFilterChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _filter = shelfNameKey(value));
    });
  }

  Set<String> get _disabledIds {
    final root = widget.disabledBranchRootId;
    if (root == null) return const {};
    return {root, ...Tag.getDescendantIds(root, widget.allTags)};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = _disabledIds;
    final entries = flattenShelfTree(widget.allTags);
    // Filtering flattens the tree: a match names its parent path instead.
    final filtering = _filter.isNotEmpty;
    final shown = filtering
        ? entries
              .where((e) => shelfNameKey(e.tag.name).contains(_filter))
              .toList()
        : entries;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.onBack != null ? 4 : 20,
            8,
            12,
            4,
          ),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: TranslationService.translate(context, 'back'),
                  onPressed: widget.onBack,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _filterController,
            onChanged: _onFilterChanged,
            decoration: InputDecoration(
              // A label, not a hint: see the shelf picker's field.
              labelText: TranslationService.translate(
                context,
                'filter_shelves_hint',
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final entry = shown[index];
              return ShelfTreeRow(
                key: ValueKey('placementRow:${entry.tag.name}'),
                name: entry.tag.name,
                depth: filtering ? 0 : entry.depth,
                subtitle: filtering || entry.depth > shelfTreeMaxIndentDepth
                    ? shelfParentPath(context, entry.ancestors)
                    : null,
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: disabled.contains(entry.tag.id)
                    ? null
                    : () => widget.onPlace(entry.tag),
              );
            },
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.onPlace(null),
                child: Text(widget.firstLevelLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
