import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';

/// Back-office screen for managing shelf hierarchy
/// Accessible from Profile > Data Management
class ShelfManagementScreen extends StatefulWidget {
  const ShelfManagementScreen({super.key});

  @override
  State<ShelfManagementScreen> createState() => _ShelfManagementScreenState();
}

class _ShelfManagementScreenState extends State<ShelfManagementScreen> {
  List<Tag> _allTags = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      final tags = await api.getTags();
      if (mounted) {
        setState(() {
          _allTags = tags;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Tag> get _rootTags => Tag.getRootTags(_allTags);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title:
            TranslationService.translate(context, 'manage_shelves') ??
            'Manage Shelves',
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip:
                TranslationService.translate(context, 'create_shelf') ??
                'Create Shelf',
            onPressed: () => _showCreateDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: TranslationService.translate(context, 'refresh'),
            onPressed: _loadTags,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTags,
              icon: const Icon(Icons.refresh),
              label: Text(
                TranslationService.translate(context, 'retry') ?? 'Retry',
              ),
            ),
          ],
        ),
      );
    }

    if (_allTags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(context, 'no_shelves_title') ??
                  'No shelves yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'create_first_shelf') ??
                  'Create your first shelf to organize your books',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreateDialog(),
              icon: const Icon(Icons.add),
              label: Text(
                TranslationService.translate(context, 'create_shelf') ??
                    'Create Shelf',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTags,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                            context,
                            'shelf_management_hint',
                          ) ??
                          'Tap a shelf to edit. Long press to move or delete.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tree view
          ..._rootTags.map((tag) => _buildTagTile(tag, 0)),
        ],
      ),
    );
  }

  Widget _buildTagTile(Tag tag, int depth) {
    final children = Tag.getDirectChildren(tag.id, _allTags);
    final hasChildren = children.isNotEmpty;
    final aggregatedCount = Tag.getAggregatedCount(tag, _allTags);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showEditDialog(tag),
              onLongPress: () => _showActionsSheet(tag),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        hasChildren ? Icons.folder : Icons.label,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tag.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '$aggregatedCount ${TranslationService.translate(context, 'books') ?? 'books'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action buttons
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip:
                          TranslationService.translate(context, 'edit') ??
                          'Edit',
                      onPressed: () => _showEditDialog(tag),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      tooltip:
                          TranslationService.translate(
                            context,
                            'more_actions',
                          ) ??
                          'More',
                      onPressed: () => _showActionsSheet(tag),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Render children recursively
        ...children.map((child) => _buildTagTile(child, depth + 1)),
      ],
    );
  }

  void _showActionsSheet(Tag tag) {
    final children = Tag.getDirectChildren(tag.id, _allTags);
    final hasChildren = children.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        hasChildren ? Icons.folder : Icons.label,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tag.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),

                // Edit
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(
                    TranslationService.translate(context, 'edit_shelf') ??
                        'Edit Shelf',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(tag);
                  },
                ),

                // Move (change parent)
                ListTile(
                  leading: const Icon(Icons.drive_file_move),
                  title: Text(
                    TranslationService.translate(context, 'move_shelf') ??
                        'Move Shelf',
                  ),
                  subtitle: Text(
                    TranslationService.translate(context, 'move_shelf_hint') ??
                        'Change parent category',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showMoveDialog(tag);
                  },
                ),

                // Add child
                ListTile(
                  leading: const Icon(Icons.create_new_folder),
                  title: Text(
                    TranslationService.translate(context, 'add_sub_shelf') ??
                        'Add Sub-Shelf',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateDialog(parentTag: tag);
                  },
                ),

                // Delete
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red[400]),
                  title: Text(
                    TranslationService.translate(context, 'delete_shelf') ??
                        'Delete Shelf',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  subtitle: hasChildren
                      ? Text(
                          TranslationService.translate(
                                context,
                                'delete_shelf_warning',
                              ) ??
                              'This will also delete ${children.length} sub-shelves',
                          style: TextStyle(color: Colors.red[300]),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(tag);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateDialog({Tag? parentTag}) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(context, 'create_shelf') ??
                'Create Shelf',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parentTag != null) ...[
                  Text(
                    '${TranslationService.translate(context, 'parent') ?? 'Parent'}: ${parentTag.fullPath}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(context, 'shelf_name') ??
                        'Shelf Name',
                    hintText:
                        TranslationService.translate(
                          context,
                          'shelf_name_hint',
                        ) ??
                        'e.g. Science Fiction',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return TranslationService.translate(
                            context,
                            'field_required',
                          ) ??
                          'This field is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _createTag(controller.text.trim(), parentTag?.id);
                }
              },
              child: Text(
                TranslationService.translate(context, 'create') ?? 'Create',
              ),
            ),
          ],
        );
      },
    );
  }

  void _showEditDialog(Tag tag) {
    final controller = TextEditingController(text: tag.name);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(context, 'edit_shelf') ?? 'Edit Shelf',
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'shelf_name') ??
                    'Shelf Name',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return TranslationService.translate(
                        context,
                        'field_required',
                      ) ??
                      'This field is required';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _updateTag(
                    tag.id,
                    controller.text.trim(),
                    tag.parentId,
                  );
                }
              },
              child: Text(
                TranslationService.translate(context, 'save') ?? 'Save',
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMoveDialog(Tag tag) {
    Tag? selectedParent;
    // Filter out the tag itself and its descendants (can't move to self or child)
    final descendants = Tag.getDescendantIds(tag.id, _allTags);
    final validParents = _allTags
        .where((t) => t.id != tag.id && !descendants.contains(t.id) && t.id > 0)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                TranslationService.translate(context, 'move_shelf') ??
                    'Move Shelf',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${TranslationService.translate(context, 'moving') ?? 'Moving'}: ${tag.name}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(
                          context,
                          'select_new_parent',
                        ) ??
                        'Select new parent:',
                  ),
                  const SizedBox(height: 8),

                  // Root option
                  RadioListTile<Tag?>(
                    value: null,
                    groupValue: selectedParent,
                    title: Text(
                      TranslationService.translate(context, 'root_level') ??
                          'Root Level (No Parent)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    secondary: const Icon(Icons.home),
                    onChanged: (value) {
                      setDialogState(() => selectedParent = value);
                    },
                  ),

                  // Parent options
                  ...validParents.map(
                    (t) => RadioListTile<Tag?>(
                      value: t,
                      groupValue: selectedParent,
                      title: Text(t.fullPath),
                      secondary: Icon(
                        Tag.getDirectChildren(t.id, _allTags).isNotEmpty
                            ? Icons.folder
                            : Icons.label,
                      ),
                      onChanged: (value) {
                        setDialogState(() => selectedParent = value);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    TranslationService.translate(context, 'cancel') ?? 'Cancel',
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateTag(tag.id, tag.name, selectedParent?.id);
                  },
                  child: Text(
                    TranslationService.translate(context, 'move') ?? 'Move',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmation(Tag tag) {
    final children = Tag.getDirectChildren(tag.id, _allTags);
    final hasChildren = children.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(context, 'delete_shelf') ??
                'Delete Shelf',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${TranslationService.translate(context, 'confirm_delete') ?? 'Are you sure you want to delete'} "${tag.name}"?',
              ),
              if (hasChildren) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[400]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                                context,
                                'delete_with_children_warning',
                              ) ??
                              'This will also delete ${children.length} sub-shelves!',
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _deleteTag(tag);
              },
              child: Text(
                TranslationService.translate(context, 'delete') ?? 'Delete',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // CRUD Operations
  Future<void> _createTag(String name, int? parentId) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.createTag(name, parentId: parentId);
      _showSuccess(
        TranslationService.translate(context, 'shelf_created') ??
            'Shelf created',
      );
      await _loadTags();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _updateTag(int id, String name, int? parentId) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);

      // Legacy tags have negative IDs - they exist in book subjects but not in tags table
      // We need to create them first before we can set their parent
      if (id < 0) {
        // Find the original tag to get its name
        final originalTag = _allTags.firstWhere((t) => t.id == id);
        // Create the tag in the database (with the new parent if specified)
        await api.createTag(originalTag.name, parentId: parentId);
        _showSuccess(
          TranslationService.translate(context, 'shelf_updated') ??
              'Shelf updated',
        );
      } else {
        // Normal update for tags that already exist in the database
        await api.updateTag(id, name, parentId: parentId);
        _showSuccess(
          TranslationService.translate(context, 'shelf_updated') ??
              'Shelf updated',
        );
      }
      await _loadTags();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);

      // Legacy tags (ID < 0) don't exist in DB - only skip if needed
      if (tag.id < 0) {
        _showSuccess(
          TranslationService.translate(context, 'shelf_deleted') ??
              'Shelf deleted',
        );
        return; // Nothing to delete from DB
      }

      // Delete children first (recursive)
      final children = Tag.getDirectChildren(tag.id, _allTags);
      for (final child in children) {
        await _deleteTagRecursive(child);
      }

      // Delete the tag itself
      await api.deleteTag(tag.id);
      _showSuccess(
        TranslationService.translate(context, 'shelf_deleted') ??
            'Shelf deleted',
      );
      await _loadTags();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteTagRecursive(Tag tag) async {
    if (tag.id < 0) return; // Skip legacy tags
    final api = Provider.of<TagRepository>(context, listen: false);
    final children = Tag.getDirectChildren(tag.id, _allTags);
    for (final child in children) {
      await _deleteTagRecursive(child);
    }
    await api.deleteTag(tag.id);
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
