import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../services/translation_service.dart';
import '../utils/app_constants.dart';

/// Widget for displaying tags in a hierarchical tree structure.
/// Only shown when [AppConstants.enableHierarchicalTags] is true.
///
/// Supports optional [searchQuery] to filter and highlight matching nodes.
class TagTreeView extends StatefulWidget {
  final List<Tag> tags;
  final Set<String> selectedTagIds;
  final Function(Tag) onTagSelected;
  final Function(Tag)? onTagLongPress;
  final bool multiSelect;
  final String? searchQuery;

  const TagTreeView({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.onTagSelected,
    this.onTagLongPress,
    this.multiSelect = true,
    this.searchQuery,
  });

  @override
  State<TagTreeView> createState() => _TagTreeViewState();
}

class _TagTreeViewState extends State<TagTreeView> {
  final Set<String> _userExpandedIds = {};

  bool get _isSearching =>
      widget.searchQuery != null && widget.searchQuery!.isNotEmpty;

  bool _isExpanded(String id) {
    if (_isSearching) return true;
    return _userExpandedIds.contains(id);
  }

  void _toggleExpansion(String id) {
    if (_isSearching) return;
    setState(() {
      if (_userExpandedIds.contains(id)) {
        _userExpandedIds.remove(id);
      } else {
        _userExpandedIds.add(id);
      }
    });
  }

  bool _tagMatchesSearch(Tag tag) {
    if (!_isSearching) return true;
    final query = widget.searchQuery!.toLowerCase();
    return tag.name.toLowerCase().contains(query);
  }

  bool _subtreeHasMatch(Tag tag) {
    if (!_isSearching) return true;
    if (_tagMatchesSearch(tag)) return true;
    return tag.children.any(_subtreeHasMatch);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConstants.enableHierarchicalTags) {
      return _buildFlatList();
    }

    final rootTags = _buildTree(widget.tags);

    if (rootTags.isEmpty) {
      return Center(
        child: Text(TranslationService.translate(context, 'no_shelves_yet')),
      );
    }

    final displayRoots = _isSearching
        ? rootTags.where(_subtreeHasMatch).toList()
        : rootTags;

    if (displayRoots.isEmpty) {
      return _buildNoMatchState();
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: displayRoots.length,
      itemBuilder: (context, index) => _buildTreeNode(displayRoots[index], 0),
    );
  }

  Widget _buildNoMatchState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'no_shelves_match'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build tree structure from flat list with parent_id
  List<Tag> _buildTree(List<Tag> flatTags) {
    final Map<String, Tag> tagMap = {};
    final List<Tag> rootTags = [];

    // First pass: create map of all tags
    for (final tag in flatTags) {
      tagMap[tag.id] = tag;
    }

    // Second pass: build tree by assigning children
    for (final tag in flatTags) {
      if (tag.parentId == null) {
        // Root tag - add to root list with children
        final children = flatTags
            .where((t) => t.parentId == tag.id)
            .map((t) => _attachChildren(t, flatTags))
            .toList();
        rootTags.add(tag.copyWithChildren(children));
      }
    }

    return rootTags;
  }

  /// Recursively attach children to a tag
  Tag _attachChildren(Tag tag, List<Tag> allTags) {
    final children = allTags
        .where((t) => t.parentId == tag.id)
        .map((t) => _attachChildren(t, allTags))
        .toList();
    return tag.copyWithChildren(children);
  }

  /// Build a single tree node with expand/collapse
  Widget _buildTreeNode(Tag tag, int depth) {
    // During search, skip subtrees with no matches
    if (_isSearching && !_subtreeHasMatch(tag)) {
      return const SizedBox.shrink();
    }

    final hasChildren = tag.children.isNotEmpty;
    final isExpanded = _isExpanded(tag.id);
    final isSelected = widget.selectedTagIds.contains(tag.id);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onTagSelected(tag),
          onLongPress: widget.onTagLongPress != null
              ? () => widget.onTagLongPress!(tag)
              : null,
          child: Container(
            padding: EdgeInsets.only(
              left: 16.0 + (depth * 24.0),
              right: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withAlpha(25)),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse button for parents
                if (hasChildren)
                  GestureDetector(
                    onTap: () => _toggleExpansion(tag.id),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_right,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 28),

                // Tag icon
                Icon(
                  hasChildren ? Icons.folder_outlined : Icons.label_outline,
                  size: 18,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),

                // Tag name (with search highlighting)
                Expanded(child: _buildTagName(tag.name, theme, isSelected)),

                // Count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${tag.count}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

                // Selection indicator (always visible in multiSelect)
                if (widget.multiSelect)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.3,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Children (if expanded)
        if (hasChildren && isExpanded)
          ...tag.children.map((child) => _buildTreeNode(child, depth + 1)),
      ],
    );
  }

  /// Build tag name with optional search highlight
  Widget _buildTagName(String name, ThemeData theme, bool isSelected) {
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      color: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface,
    );

    if (!_isSearching) {
      return Text(name, style: baseStyle);
    }

    final query = widget.searchQuery!.toLowerCase();
    final nameLower = name.toLowerCase();
    final matchStart = nameLower.indexOf(query);

    if (matchStart < 0) {
      return Text(name, style: baseStyle);
    }

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: name.substring(0, matchStart)),
          TextSpan(
            text: name.substring(matchStart, matchStart + query.length),
            style: TextStyle(
              backgroundColor: theme.colorScheme.primaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: name.substring(matchStart + query.length)),
        ],
      ),
    );
  }

  /// Fallback: flat list when hierarchical tags disabled
  Widget _buildFlatList() {
    if (widget.tags.isEmpty) {
      return Center(
        child: Text(TranslationService.translate(context, 'no_shelves_yet')),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: widget.tags.length,
      itemBuilder: (context, index) {
        final tag = widget.tags[index];
        final isSelected = widget.selectedTagIds.contains(tag.id);
        final theme = Theme.of(context);

        return ListTile(
          leading: Icon(
            Icons.label_outline,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
          title: Text(tag.name),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${tag.count}'),
          ),
          selected: isSelected,
          onTap: () => widget.onTagSelected(tag),
          onLongPress: widget.onTagLongPress != null
              ? () => widget.onTagLongPress!(tag)
              : null,
        );
      },
    );
  }
}
