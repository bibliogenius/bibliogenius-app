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
  // Use a local copy for the dialog
  late List<String> _currentSelection;

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedTags);
  }

  void _removeTag(String tag) {
    setState(() {
      _currentSelection.remove(tag);
      widget.onTagsChanged(_currentSelection);
    });
  }

  Future<void> _showSelectionDialog() async {
    final api = Provider.of<TagRepository>(context, listen: false);

    // Fetch fresh tags
    final tags = await api.getTags();

    if (!mounted) return;

    // We map strings back to IDs for the tree view
    // Note: This relies on exact string match of fullPath
    final selectedIds = tags
        .where((t) => _currentSelection.contains(t.fullPath))
        .map((t) => t.id)
        .toSet();

    await showDialog(
      context: context,
      builder: (context) => _TagSelectionDialog(
        allTags: tags,
        initialSelectedIds: selectedIds,
        onSelectionChanged: (newSelectionPaths) {
          setState(() {
            _currentSelection = newSelectionPaths;
            widget.onTagsChanged(_currentSelection);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Text(
          TranslationService.translate(context, 'tags_label'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Selected Tags Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._currentSelection.map((tagPath) {
              // Extract leaf name for display, keep full path in tooltip
              final leafName = tagPath.split(' > ').last;
              return Tooltip(
                message: tagPath,
                child: Chip(
                  label: Text(leafName),
                  onDeleted: () => _removeTag(tagPath),
                ),
              );
            }),

            // Add Button
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(
                TranslationService.translate(context, 'add_tag') ?? 'Add',
              ),
              onPressed: _showSelectionDialog,
            ),
          ],
        ),
      ],
    );
  }
}

class _TagSelectionDialog extends StatefulWidget {
  final List<Tag> allTags;
  final Set<int> initialSelectedIds;
  final Function(List<String>) onSelectionChanged;

  const _TagSelectionDialog({
    required this.allTags,
    required this.initialSelectedIds,
    required this.onSelectionChanged,
  });

  @override
  State<_TagSelectionDialog> createState() => _TagSelectionDialogState();
}

class _TagSelectionDialogState extends State<_TagSelectionDialog> {
  late Set<int> _selectedIds;
  late List<Tag> _tags;
  bool _isCreating = false;

  // New Tag Form
  final _newTagNameController = TextEditingController();
  Tag? _parentTagForNew;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _tags = List.from(widget.allTags);
  }

  @override
  void dispose() {
    _newTagNameController.dispose();
    super.dispose();
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

      setState(() {
        _tags.add(newTag);
        // Auto-select the new tag
        _selectedIds.add(newTag.id);
        _newTagNameController.clear();
        _parentTagForNew = null;
        _isCreating = false;

        // Refresh local allTags list if we want to show it in the tree immediately
        // (Note: TagTreeView might need a rebuild key or new list instance)
        _tags = List.from(_tags);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created tag: ${newTag.fullPath}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating tag: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isCreating = false);
    }
  }

  void _finish() {
    // Map IDs back to full paths
    final selectedPaths = _tags
        .where((t) => _selectedIds.contains(t.id))
        .map((t) => t.fullPath)
        .toList();

    widget.onSelectionChanged(selectedPaths);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            TranslationService.translate(context, 'manage_tags') ??
                'Manage Tags',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            // Tree View
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TagTreeView(
                  tags: _tags,
                  selectedTagIds: _selectedIds,
                  onTagSelected: _toggleTag,
                  multiSelect: true,
                ),
              ),
            ),

            const Divider(height: 32),

            // Create New Tag Section
            Text(
              TranslationService.translate(context, 'create_new_tag'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                TextField(
                  controller: _newTagNameController,
                  decoration: InputDecoration(
                    hintText: TranslationService.translate(
                      context,
                      'tag_name_hint',
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: PopupMenuButton<Tag?>(
                        tooltip: 'Select Parent (Optional)',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _parentTagForNew == null
                                      ? TranslationService.translate(
                                          context,
                                          'root_tag',
                                        )
                                      : _parentTagForNew!.name,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        itemBuilder: (context) {
                          final validParents = _tags
                              .where((t) => t.id > 0)
                              .toList();
                          return [
                            PopupMenuItem<Tag?>(
                              value: null,
                              child: Text(
                                TranslationService.translate(
                                  context,
                                  'root_tag',
                                ),
                              ),
                            ),
                            ...validParents.map(
                              (t) => PopupMenuItem<Tag?>(
                                value: t,
                                child: Text(
                                  t.fullPath,
                                  style: const TextStyle(fontSize: 12),
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
                    const SizedBox(width: 8),
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
                          : const Icon(Icons.add),
                      onPressed: _isCreating ? null : _createNewTag,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _finish,
          child: Text(TranslationService.translate(context, 'done')),
        ),
      ],
    );
  }
}
