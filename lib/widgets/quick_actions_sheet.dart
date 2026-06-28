import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/quick_action_registry.dart';
import '../services/translation_service.dart';
import '../utils/app_constants.dart';
import 'configurable_action_card.dart';
import 'invite_share_sheet.dart';

class QuickActionsSheet extends StatelessWidget {
  final List<Widget>? contextualActions;
  final VoidCallback? onBookAdded;
  final VoidCallback? onShelfCreated;
  final String? preSelectedShelfId;
  final String? preSelectedCollectionId;
  final String? preSelectedCollectionName;
  final String? destinationName;
  final Widget? thirdSlotOverride;

  const QuickActionsSheet({
    super.key,
    this.contextualActions,
    this.onBookAdded,
    this.onShelfCreated,
    this.preSelectedShelfId,
    this.preSelectedCollectionId,
    this.preSelectedCollectionName,
    this.destinationName,
    this.thirdSlotOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
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
                      ? Colors.purple.withValues(alpha: 0.2)
                      : Colors.purple.withValues(alpha: 0.1),
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

          // Search Bar with action suggestions (always visible)
          _ActionSearchBar(onBookAdded: onBookAdded),
          const SizedBox(height: 16),

          // Primary Button: Add Book
          ...[
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  final extra = <String, dynamic>{};
                  if (preSelectedShelfId != null) {
                    extra['shelfId'] = preSelectedShelfId;
                    extra['shelfName'] = destinationName;
                  }
                  if (preSelectedCollectionId != null) {
                    extra['collectionId'] = preSelectedCollectionId;
                    extra['collectionName'] = preSelectedCollectionName;
                  }
                  final result = await router.push(
                    '/books/add',
                    extra: extra.isNotEmpty ? extra : null,
                  );
                  if (result is String) {
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
                        Theme.of(context).primaryColor.withValues(alpha: 0.8),
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
                        Flexible(
                          child: Text(
                            destinationName != null
                                ? '${TranslationService.translate(context, 'add_book_to_title')} $destinationName'
                                : TranslationService.translate(
                                    context,
                                    'add_book_button',
                                  ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
              Expanded(
                child: QuickActionCard(
                  icon: Icons.qr_code_scanner,
                  color: Colors.orange,
                  label: TranslationService.translate(
                    context,
                    'quick_scan_barcode',
                  ),
                  onTap: () async {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);

                    final isbn = await router.push<String>('/scan');
                    if (isbn != null) {
                      final addExtra = <String, dynamic>{'isbn': isbn};
                      if (preSelectedShelfId != null) {
                        addExtra['shelfId'] = preSelectedShelfId;
                        addExtra['shelfName'] = destinationName;
                      }
                      if (preSelectedCollectionId != null) {
                        addExtra['collectionId'] = preSelectedCollectionId;
                        addExtra['collectionName'] = preSelectedCollectionName;
                      }
                      final result = await router.push(
                        '/books/add',
                        extra: addExtra,
                      );
                      if (result != null) {
                        if (onBookAdded != null) onBookAdded!();
                        if (result is String) {
                          router.push('/books/$result');
                        }
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickActionCard(
                  icon: Icons.travel_explore,
                  color: Colors.blue,
                  label: TranslationService.translate(
                    context,
                    'quick_search_online',
                  ),
                  onTap: () async {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    final result = await router.push('/search/external');
                    if (result == true && onBookAdded != null) {
                      onBookAdded!();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    thirdSlotOverride ??
                    ConfigurableActionCard(
                      slotKey: 'quick_action_custom_slot',
                      defaultActionId: 'share_library',
                      allowedActionIds: const [
                        'share_library',
                        'inventory',
                        'create_shelf',
                        'add_manual',
                      ],
                      handlers: {
                        'share_library': () {
                          final navState = Navigator.of(
                            context,
                            rootNavigator: true,
                          );
                          Navigator.pop(context);
                          showInviteShareSheet(navState.context);
                        },
                        'inventory': () =>
                            showShelfPickerForInventory(context, onBookAdded),
                        'create_shelf': () =>
                            showCreateShelfDialog(context, onShelfCreated),
                        'add_manual': () {
                          final router = GoRouter.of(context);
                          Navigator.pop(context);
                          router.push('/books/add');
                        },
                      },
                    ),
              ),
            ],
          ),

          // Contextual Actions
          if (contextualActions != null && contextualActions!.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...contextualActions!,
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Builds a Map of VoidCallbacks for all common navigable actions.
  /// Close the sheet and navigate. Page-specific handlers can override entries.
  static Map<String, VoidCallback> buildCommonHandlers(
    BuildContext context, {
    VoidCallback? onDone,
  }) {
    final router = GoRouter.of(context);
    void go(String route, [Object? extra]) {
      Navigator.pop(context);
      router.push(route, extra: extra).then((_) {
        onDone?.call();
      });
    }

    return {
      'scan_barcode': () => go('/scan'),
      'search_online': () => go('/search/external'),
      'add_manual': () => go('/books/add'),
      'batch_scan': () => go('/scan', {'batch': true}),
      'import_csv': () => go('/migration-wizard'),
      'import_gleeph': () => go('/migration-wizard'),
      'import_goodreads': () => go('/migration-wizard'),
      'manage_shelves': () => go('/shelves-management'),
      'my_contacts': () => go('/contacts'),
      'inventory': () => showShelfPickerForInventory(context, onDone),
      'create_shelf': () => showCreateShelfDialog(context, onDone),
      'share_library': () {
        final navState = Navigator.of(context, rootNavigator: true);
        Navigator.pop(context);
        showInviteShareSheet(navState.context);
      },
    };
  }

  // --- Shared action dialogs (used by cards and search bar) ---

  static void showShelfPickerForInventory(
    BuildContext context,
    VoidCallback? onBookAdded,
  ) {
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final router = GoRouter.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<List<Tag>>(
          future: tagRepo.getTags(),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final tags = snapshot.data ?? [];
            if (tags.isEmpty) {
              return AlertDialog(
                title: Text(
                  TranslationService.translate(context, 'quick_inventory') ??
                      'Inventory',
                ),
                content: Text(
                  TranslationService.translate(
                        context,
                        'no_shelves_for_inventory',
                      ) ??
                      'Create a shelf first to use inventory mode.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      TranslationService.translate(context, 'ok') ?? 'OK',
                    ),
                  ),
                ],
              );
            }
            return SimpleDialog(
              title: Text(
                TranslationService.translate(
                      context,
                      'choose_shelf_for_inventory',
                    ) ??
                    'Choose a shelf',
              ),
              children: tags.map((tag) {
                final displayName = tag.fullPath ?? tag.name;
                return SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                    final result = await router.push(
                      '/scan',
                      extra: {
                        'shelfId': tag.name,
                        'shelfName': displayName,
                        'batch': true,
                      },
                    );
                    if (result == true) {
                      onBookAdded?.call();
                      // Navigate to the shelf to show the result
                      router.go(
                        '/shelves?tag=${Uri.encodeComponent(tag.name)}',
                      );
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.label_outline,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${tag.count}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  static void showCreateShelfDialog(
    BuildContext context,
    VoidCallback? onShelfCreated,
  ) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final api = Provider.of<TagRepository>(context, listen: false);
    String? selectedParentId;

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
                    TranslationService.translate(
                          stateContext,
                          'create_shelf',
                        ) ??
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
                            labelText:
                                TranslationService.translate(
                                  stateContext,
                                  'shelf_name',
                                ) ??
                                'Shelf Name',
                            hintText:
                                TranslationService.translate(
                                  stateContext,
                                  'shelf_name_hint',
                                ) ??
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
                        if (AppConstants.enableHierarchicalTags &&
                            shelves.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String?>(
                            value: selectedParentId,
                            decoration: InputDecoration(
                              labelText:
                                  TranslationService.translate(
                                    stateContext,
                                    'parent_shelf',
                                  ) ??
                                  'Parent Shelf (optional)',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  TranslationService.translate(
                                        stateContext,
                                        'none',
                                      ) ??
                                      'None (root level)',
                                ),
                              ),
                              ...shelves.map((shelf) {
                                final name = shelf.fullPath ?? shelf.name;
                                return DropdownMenuItem<String?>(
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
                          final messenger = ScaffoldMessenger.of(context);
                          final successText =
                              TranslationService.translate(
                                context,
                                'shelf_created',
                              ) ??
                              'Shelf created';

                          Navigator.pop(dialogContext);
                          Navigator.pop(context);

                          try {
                            await api.createTag(
                              controller.text.trim(),
                              parentId: selectedParentId,
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(successText),
                                backgroundColor: Colors.green,
                              ),
                            );
                            onShelfCreated?.call();
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
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
}

// --- Search bar with action suggestions (command palette) ---

/// Route mapping for actions executable from the search bar.
/// Actions needing complex flows (dialogs, pickers) are excluded.
const _actionRoutes = <String, String>{
  'scan_barcode': '/scan',
  'search_online': '/search/external',
  'add_manual': '/books/add',
  'import_csv': '/migration-wizard',
  'import_gleeph': '/migration-wizard',
  'import_goodreads': '/migration-wizard',
  'manage_shelves': '/shelves-management',
  'my_contacts': '/contacts',
  'share_library': '/migration-wizard',
};

const _actionExtras = <String, Map<String, dynamic>>{
  'batch_scan': {'batch': true},
};

class _ActionSearchBar extends StatefulWidget {
  final VoidCallback? onBookAdded;

  const _ActionSearchBar({this.onBookAdded});

  @override
  State<_ActionSearchBar> createState() => _ActionSearchBarState();
}

class _ActionSearchBarState extends State<_ActionSearchBar> {
  final _controller = TextEditingController();
  List<QuickActionDef> _suggestions = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      if (value.length < 2) {
        _suggestions = [];
      } else {
        _suggestions = QuickActionRegistry.search(value)
            .where(
              (a) =>
                  _actionRoutes.containsKey(a.id) ||
                  _actionExtras.containsKey(a.id),
            )
            .take(4)
            .toList();
      }
    });
  }

  void _executeAction(QuickActionDef action) {
    final router = GoRouter.of(context);
    Navigator.pop(context);

    final route = _actionRoutes[action.id];
    final extras = _actionExtras[action.id];

    if (route != null) {
      if (action.id == 'scan_barcode') {
        // Scan has special flow: scan -> add book
        router.push<String>('/scan').then((isbn) {
          if (isbn != null) {
            router.push('/books/add', extra: {'isbn': isbn}).then((result) {
              if (result != null) widget.onBookAdded?.call();
            });
          }
        });
      } else {
        router.push(route, extra: extras);
      }
    } else if (extras != null) {
      // batch_scan: route is /scan with extras
      router.push('/scan', extra: extras);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: TranslationService.translate(
              context,
              'search_actions_placeholder',
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
          onChanged: _onChanged,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context);
              context.go('/books?q=${Uri.encodeComponent(value)}');
            }
          },
        ),
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((action) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _executeAction(action),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(action.icon, color: action.color, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              TranslationService.translate(
                                context,
                                action.labelKey,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[800],
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
