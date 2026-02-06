import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/translation_service.dart';
import '../utils/app_constants.dart';

class QuickActionsSheet extends StatelessWidget {
  final List<Widget>? contextualActions;
  final bool hideGenericActions;
  final VoidCallback? onBookAdded; // Callback when a book is added
  final VoidCallback? onShelfCreated; // Callback when a shelf is created

  const QuickActionsSheet({
    super.key,
    this.contextualActions,
    this.hideGenericActions = false,
    this.onBookAdded,
    this.onShelfCreated,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if we are on mobile (bottom sheet) or desktop (dialog)
    // The parent calling code handles the showModalBottomSheet vs showDialog logic.
    // This widget just builds the content.
    // However, for bottom sheet we often want a drag handle or specific padding.

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      // Add SafeArea and keyboard padding
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.purple.withOpacity(0.2)
                      : Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                TranslationService.translate(context, 'quick_actions_title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Search Bar (Generic)
          if (!hideGenericActions) ...[
            TextField(
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'search_library_placeholder',
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.pop(context); // Close sheet
                  // Navigate to book list with search query
                  context.go('/books?q=${Uri.encodeComponent(value)}');
                }
              },
            ),
            const SizedBox(height: 16),

            // Primary Button: Add Book
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  final result = await router.push('/books/add');
                  if (result is int) {
                    router.push('/books/$result');
                  }
                },
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
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          TranslationService.translate(
                            context,
                            'add_book_button',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Quick Actions Grid
          Row(
            children: [
              _buildQuickActionCard(
                context,
                icon: Icons.qr_code_scanner,
                color: Colors.orange,
                label: 'quick_scan_barcode',
                onTap: () async {
                  // Capture the router BEFORE popping the sheet
                  // This failsafe ensures we have a valid navigator even after the widget is disposed
                  final router = GoRouter.of(context);
                  Navigator.pop(context);

                  // Use the captured router for the async sequence
                  final isbn = await router.push<String>('/scan');
                  if (isbn != null) {
                    final result = await router.push(
                      '/books/add',
                      extra: {'isbn': isbn},
                    );
                    if (result != null) {
                      if (onBookAdded != null) onBookAdded!();
                      if (result is int) {
                        router.push('/books/$result');
                      }
                    }
                  }
                },
              ),
              const SizedBox(width: 12),
              _buildQuickActionCard(
                context,
                icon: Icons.travel_explore, // Globe with search
                color: Colors.blue,
                label: 'quick_search_online',
                onTap: () async {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  final result = await router.push('/search/external');
                  if (result == true && onBookAdded != null) {
                    onBookAdded!();
                  }
                },
              ),
              const SizedBox(width: 12),
              _buildQuickActionCard(
                context,
                icon: Icons.local_library_outlined, // Book/Person
                color: Colors.purple,
                label: 'quick_borrow_book',
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/requests');
                },
              ),
              const SizedBox(width: 12),
              _buildQuickActionCard(
                context,
                icon: Icons.create_new_folder_outlined,
                color: Colors.teal,
                label: 'quick_create_shelf',
                onTap: () => _showCreateShelfDialog(context),
              ),
            ],
          ),

          // Contextual Actions
          if (contextualActions != null && contextualActions!.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            // We can wrap them in a Column or list
            ...contextualActions!,
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  TranslationService.translate(context, label),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateShelfDialog(BuildContext context) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final api = Provider.of<TagRepository>(context, listen: false);
    int? selectedParentId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<List<Tag>>(
          future: api.getTags(),
          builder: (futureContext, snapshot) {
            final shelves = snapshot.data ?? <Tag>[];

            return StatefulBuilder(
              builder: (stateContext, setDialogState) {
                return AlertDialog(
                  title: Text(
                    TranslationService.translate(stateContext, 'create_shelf') ??
                        'Create Shelf',
                  ),
                  content: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: TranslationService.translate(
                                    stateContext, 'shelf_name') ??
                                'Shelf Name',
                            hintText: TranslationService.translate(
                                    stateContext, 'shelf_name_hint') ??
                                'e.g. Science Fiction',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return TranslationService.translate(
                                    stateContext,
                                    'field_required',
                                  ) ??
                                  'This field is required';
                            }
                            return null;
                          },
                        ),
                        if (AppConstants.enableHierarchicalTags && shelves.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int?>(
                            value: selectedParentId,
                            decoration: InputDecoration(
                              labelText: TranslationService.translate(
                                      stateContext, 'parent_shelf') ??
                                  'Parent Shelf (optional)',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  TranslationService.translate(
                                          stateContext, 'none') ??
                                      'None (root level)',
                                ),
                              ),
                              ...shelves.map((shelf) {
                                final name = shelf.fullPath ?? shelf.name;
                                return DropdownMenuItem<int?>(
                                  value: shelf.id,
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                selectedParentId = value;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        TranslationService.translate(stateContext, 'cancel') ??
                            'Cancel',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(dialogContext);
                          Navigator.pop(context); // Close the quick actions sheet
                          await _createShelf(
                            context,
                            controller.text.trim(),
                            parentId: selectedParentId,
                          );
                        }
                      },
                      child: Text(
                        TranslationService.translate(stateContext, 'create') ??
                            'Create',
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _createShelf(BuildContext context, String name,
      {int? parentId}) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.createTag(name, parentId: parentId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'shelf_created') ??
                  'Shelf created',
            ),
            backgroundColor: Colors.green,
          ),
        );
        onShelfCreated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }
}
