import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/collection.dart';
import '../data/repositories/collection_repository.dart';
import '../services/translation_service.dart';

class CollectionSelector extends StatefulWidget {
  final List<Collection> selectedCollections;
  final Function(List<Collection>) onChanged;

  const CollectionSelector({
    super.key,
    required this.selectedCollections,
    required this.onChanged,
  });

  @override
  State<CollectionSelector> createState() => _CollectionSelectorState();
}

class _CollectionSelectorState extends State<CollectionSelector> {
  // Use a local copy for the dialog
  late List<Collection> _currentSelection;

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedCollections);
  }

  void _removeCollection(Collection collection) {
    setState(() {
      _currentSelection.removeWhere((c) => c.id == collection.id);
      widget.onChanged(_currentSelection);
    });
  }

  Future<void> _showSelectionDialog() async {
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);

    // Fetch fresh collections
    final allCollections = await collectionRepo.getCollections();

    if (!mounted) return;

    // Use IDs to track selection in the dialog for easier comparison
    final selectedIds = _currentSelection.map((c) => c.id).toSet();

    await showDialog(
      context: context,
      builder: (context) => _CollectionSelectionDialog(
        allCollections: allCollections,
        initialSelectedIds: selectedIds,
        onSelectionChanged: (newlySelectedCollections) {
          setState(() {
            _currentSelection = newlySelectedCollections;
            widget.onChanged(_currentSelection);
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
          TranslationService.translate(context, 'collections_label'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Selected Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._currentSelection.map((collection) {
              return Chip(
                label: Text(collection.name),
                onDeleted: () => _removeCollection(collection),
              );
            }),

            // Add Button
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(
                TranslationService.translate(context, 'add_collection'),
              ),
              onPressed: _showSelectionDialog,
            ),
          ],
        ),
      ],
    );
  }
}

class _CollectionSelectionDialog extends StatefulWidget {
  final List<Collection> allCollections;
  final Set<String> initialSelectedIds;
  final Function(List<Collection>) onSelectionChanged;

  const _CollectionSelectionDialog({
    required this.allCollections,
    required this.initialSelectedIds,
    required this.onSelectionChanged,
  });

  @override
  State<_CollectionSelectionDialog> createState() =>
      _CollectionSelectionDialogState();
}

class _CollectionSelectionDialogState
    extends State<_CollectionSelectionDialog> {
  late Set<String> _selectedIds;
  late List<Collection> _collections;
  bool _isCreating = false;

  // New Collection Form
  final _newCollectionNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _collections = List.from(widget.allCollections);
  }

  @override
  void dispose() {
    _newCollectionNameController.dispose();
    super.dispose();
  }

  void _toggleCollection(Collection collection) {
    setState(() {
      if (_selectedIds.contains(collection.id)) {
        _selectedIds.remove(collection.id);
      } else {
        _selectedIds.add(collection.id);
      }
    });
  }

  Future<void> _createNewCollection() async {
    if (_newCollectionNameController.text.trim().isEmpty) return;

    final name = _newCollectionNameController.text.trim();

    setState(() => _isCreating = true);

    try {
      final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
      final newCollection = await collectionRepo.createCollection(name);

      setState(() {
        _collections.insert(0, newCollection); // Add to top
        // Auto-select the new collection
        _selectedIds.add(newCollection.id);
        _newCollectionNameController.clear();
        _isCreating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'collection_created')}: ${newCollection.name}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_creating_collection')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isCreating = false);
    }
  }

  void _finish() {
    // Map IDs back to Collection objects
    final selectedCollections = _collections
        .where((c) => _selectedIds.contains(c.id))
        .toList();

    widget.onSelectionChanged(selectedCollections);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(TranslationService.translate(context, 'manage_collections')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // List View section with max height
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: _collections.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            TranslationService.translate(
                              context,
                              'no_collections',
                            ),
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _collections.length,
                          itemBuilder: (context, index) {
                            final collection = _collections[index];
                            final isSelected = _selectedIds.contains(
                              collection.id,
                            );
                            return CheckboxListTile(
                              title: Text(
                                collection.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              value: isSelected,
                              onChanged: (_) => _toggleCollection(collection),
                              activeColor: Theme.of(context).primaryColor,
                              controlAffinity: ListTileControlAffinity.trailing,
                              dense: true,
                            );
                          },
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Create New Collection Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                      context,
                      'create_new_collection',
                    ),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCollectionNameController,
                          decoration: InputDecoration(
                            hintText: TranslationService.translate(
                              context,
                              'collection_name_hint',
                            ),
                            isDense: true,
                            fillColor: Colors.white,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onSubmitted: (_) => _createNewCollection(),
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
                        onPressed: _isCreating ? null : _createNewCollection,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
      actions: [
        ElevatedButton(
          onPressed: _finish,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: Text(
                TranslationService.translate(context, 'done'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
