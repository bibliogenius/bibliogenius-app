import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/translation_service.dart';
import 'tag_tree_view.dart';

class HierarchicalTagSelector extends StatefulWidget {
  final List<String> selectedTags;
  final Function(List<String>) onTagsChanged;

  const HierarchicalTagSelector({
    super.key,
    required this.selectedTags,
    required this.onTagsChanged,
  });

  @override
  State<HierarchicalTagSelector> createState() =>
      _HierarchicalTagSelectorState();
}

class _HierarchicalTagSelectorState extends State<HierarchicalTagSelector> {
  late List<String> _currentSelection;

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedTags);
  }

  @override
  void didUpdateWidget(covariant HierarchicalTagSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTags != oldWidget.selectedTags) {
      _currentSelection = List.from(widget.selectedTags);
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _currentSelection.remove(tag);
      widget.onTagsChanged(_currentSelection);
    });
  }

  Future<void> _showShelfPicker() async {
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final tags = await tagRepo.getTags();
    if (!mounted) return;

    final selectedIds = tags
        .where((t) => _currentSelection.contains(t.fullPath))
        .map((t) => t.id)
        .toSet();

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ShelfPickerSheet(
        allTags: tags,
        initialSelectedIds: selectedIds,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _currentSelection = result;
        widget.onTagsChanged(_currentSelection);
      });
    }
  }

  /// Build a concise display label for a tag path.
  /// 1 level: "Fiction"
  /// 2 levels: "Fiction > Policier"
  /// 3+ levels: "... > Parent > Leaf"
  String _displayPath(String tagPath) {
    final parts = tagPath.split(' > ');
    if (parts.length <= 2) return parts.join(' \u203a ');
    return '\u2026 \u203a ${parts[parts.length - 2]} \u203a ${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.shelves, size: 20, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(context, 'tags_label'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color.lerp(theme.colorScheme.primary, Colors.black, 0.25),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TranslationService.translate(context, 'tags_helper'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Selected Tags Chips + Add Button
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._currentSelection.map((tagPath) {
              final isNested = tagPath.contains(' > ');
              return Tooltip(
                message: tagPath,
                child: Chip(
                  avatar: Icon(
                    isNested
                        ? Icons.subdirectory_arrow_right_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(_displayPath(tagPath)),
                  onDeleted: () => _removeTag(tagPath),
                ),
              );
            }),

            // Add Button
            ActionChip(
              avatar: Icon(
                Icons.library_add_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                TranslationService.translate(context, 'add_tag'),
              ),
              onPressed: _showShelfPicker,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Sheet Picker
// ---------------------------------------------------------------------------

class _ShelfPickerSheet extends StatefulWidget {
  final List<Tag> allTags;
  final Set<int> initialSelectedIds;

  const _ShelfPickerSheet({
    required this.allTags,
    required this.initialSelectedIds,
  });

  @override
  State<_ShelfPickerSheet> createState() => _ShelfPickerSheetState();
}

class _ShelfPickerSheetState extends State<_ShelfPickerSheet> {
  late Set<int> _selectedIds;
  late List<Tag> _tags;
  String _searchQuery = '';
  bool _isCreating = false;
  bool _showCreateForm = false;

  final _searchController = TextEditingController();
  final _newTagNameController = TextEditingController();
  Tag? _parentTagForNew;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _tags = List.from(widget.allTags);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newTagNameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _searchQuery = query.trim());
      }
    });
  }

  void _toggleTag(Tag tag) {
    setState(() {
      if (_selectedIds.contains(tag.id)) {
        _selectedIds.remove(tag.id);
      } else {
        _selectedIds.add(tag.id);
      }
    });
  }

  Future<void> _createNewTag() async {
    if (_newTagNameController.text.trim().isEmpty) return;

    final name = _newTagNameController.text.trim();
    final parentId = _parentTagForNew?.id;

    setState(() => _isCreating = true);

    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      final newTag = await api.createTag(name, parentId: parentId);

      if (!mounted) return;

      setState(() {
        _tags.add(newTag);
        _selectedIds.add(newTag.id);
        _newTagNameController.clear();
        _parentTagForNew = null;
        _isCreating = false;
        _showCreateForm = false;
        _tags = List.from(_tags);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(newTag.fullPath)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isCreating = false);
    }
  }

  void _finish() {
    final selectedPaths = _tags
        .where((t) => _selectedIds.contains(t.id))
        .map((t) => t.fullPath)
        .toList();

    Navigator.pop(context, selectedPaths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selectedIds.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.shelves,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                              context, 'manage_tags'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip:
                        TranslationService.translate(context, 'close'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: TranslationService.translate(
                          context, 'search_shelves_hint'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip:
                              TranslationService.translate(
                                      context, 'clear'),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Tree view
            Expanded(
              child: _tags.isEmpty
                  ? _buildEmptyState(theme)
                  : TagTreeView(
                      tags: _tags,
                      selectedTagIds: _selectedIds,
                      onTagSelected: _toggleTag,
                      multiSelect: true,
                      searchQuery: _searchQuery.isNotEmpty
                          ? _searchQuery
                          : null,
                    ),
            ),

            // Create new tag section
            _buildCreateSection(theme),

            // Bottom bar with selected count + Done
            _buildBottomBar(theme, selectedCount),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shelves,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            TranslationService.translate(context, 'no_shelves_yet'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            TranslationService.translate(context, 'create_new_tag'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSection(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: () => setState(() => _showCreateForm = !_showCreateForm),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                        context, 'create_new_tag'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _showCreateForm
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: _buildCreateForm(theme),
          crossFadeState: _showCreateForm
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildCreateForm(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTagNameController,
                  decoration: InputDecoration(
                    hintText: TranslationService.translate(
                        context, 'tag_name_hint'),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _createNewTag(),
                ),
              ),
              const SizedBox(width: 8),
              // Parent selector
              Tooltip(
                message: TranslationService.translate(
                        context, 'root_tag'),
                child: PopupMenuButton<Tag?>(
                  icon: Icon(
                    Icons.account_tree_outlined,
                    color: _parentTagForNew != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  itemBuilder: (context) {
                    final validParents =
                        _tags.where((t) => t.id > 0).toList();
                    return [
                      PopupMenuItem<Tag?>(
                        value: null,
                        child: Row(
                          children: [
                            const Icon(Icons.home_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(TranslationService.translate(
                                context, 'root_tag')),
                          ],
                        ),
                      ),
                      ...validParents.map(
                        (t) => PopupMenuItem<Tag?>(
                          value: t,
                          child: Padding(
                            padding: EdgeInsets.only(
                                left: (t.fullPath.split(' > ').length -
                                        1) *
                                    16.0),
                            child: Text(
                              t.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ];
                  },
                  onSelected: (Tag? parent) {
                    setState(() => _parentTagForNew = parent);
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                icon: _isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add, size: 20),
                tooltip: TranslationService.translate(
                    context, 'create_new_tag'),
                onPressed: _isCreating ? null : _createNewTag,
              ),
            ],
          ),
          if (_parentTagForNew != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _parentTagForNew!.fullPath,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, int selectedCount) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (selectedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$selectedCount ${TranslationService.translate(context, 'shelves_selected')}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                  TranslationService.translate(context, 'done')),
            ),
          ],
        ),
      ),
    );
  }
}
