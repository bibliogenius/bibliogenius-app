import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/collection.dart';
import '../data/repositories/collection_repository.dart';
import '../services/translation_service.dart';

/// Inline collection selector with autocomplete and create-on-submit.
///
/// Matches the tag field UX: type to search existing collections, press
/// Enter or tap "+" to add (creating a new collection if needed).
/// Selected collections appear as deletable chips below the field.
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
  late List<Collection> _currentSelection;
  // Assigned by the Autocomplete fieldViewBuilder; Autocomplete manages its
  // lifecycle so we must NOT dispose it ourselves.
  TextEditingController _fieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedCollections);
  }

  @override
  void didUpdateWidget(covariant CollectionSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCollections != oldWidget.selectedCollections) {
      _currentSelection = List.from(widget.selectedCollections);
    }
  }

  void _removeCollection(Collection collection) {
    setState(() {
      _currentSelection.removeWhere((c) => c.id == collection.id);
      widget.onChanged(_currentSelection);
    });
  }

  /// Add an existing collection by exact object reference.
  void _addExisting(Collection collection) {
    if (_currentSelection.any((c) => c.id == collection.id)) return;
    setState(() {
      _currentSelection.add(collection);
      widget.onChanged(_currentSelection);
      _fieldController.clear();
    });
  }

  /// Resolve the current text field value: pick an existing collection whose
  /// name matches (case-insensitive) or create a new one, then add it.
  Future<void> _addFromText() async {
    final text = _fieldController.text.trim();
    if (text.isEmpty) return;

    final collectionRepo =
        Provider.of<CollectionRepository>(context, listen: false);

    // Check if an existing collection matches
    try {
      final all = await collectionRepo.getCollections();
      final match = all.cast<Collection?>().firstWhere(
            (c) => c!.name.toLowerCase() == text.toLowerCase(),
            orElse: () => null,
          );

      if (match != null) {
        _addExisting(match);
        return;
      }
    } catch (_) {}

    // No match: create a new collection
    try {
      final created = await collectionRepo.createCollection(text);
      if (!mounted) return;
      _addExisting(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'error_creating_collection')}: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: Icon(Icons.folder_outlined, size: 20, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(context, 'collections_label'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color.lerp(Theme.of(context).colorScheme.primary, Colors.black, 0.25),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TranslationService.translate(context, 'collections_helper'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Autocomplete field
        Autocomplete<Collection>(
          optionsBuilder: (TextEditingValue textEditingValue) async {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<Collection>.empty();
            }
            try {
              final collectionRepo =
                  Provider.of<CollectionRepository>(context, listen: false);
              final all = await collectionRepo.getCollections();
              final selectedIds =
                  _currentSelection.map((c) => c.id).toSet();
              return all.where((c) =>
                  c.name
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()) &&
                  !selectedIds.contains(c.id));
            } catch (_) {
              return const Iterable<Collection>.empty();
            }
          },
          displayStringForOption: (Collection c) => c.name,
          onSelected: (Collection selection) {
            _addExisting(selection);
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            _fieldController = textEditingController;
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'add_collection_hint',
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: TranslationService.translate(
                    context,
                    'add_collection',
                  ),
                  onPressed: () {
                    if (textEditingController.text.trim().isNotEmpty) {
                      _addFromText();
                    }
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onFieldSubmitted: (String value) {
                if (value.trim().isNotEmpty) {
                  _addFromText();
                }
                focusNode.requestFocus();
              },
            );
          },
        ),
        const SizedBox(height: 12),

        // Selected chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _currentSelection.map((collection) {
            return Chip(
              label: Text(collection.name),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () => _removeCollection(collection),
            );
          }).toList(),
        ),
      ],
    );
  }
}
