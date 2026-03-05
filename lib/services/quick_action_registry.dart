import 'package:flutter/material.dart';

/// Metadata for a quick action available in the app.
/// Handlers are NOT defined here - they live in the widgets/screens
/// because they need BuildContext and navigation.
class QuickActionDef {
  final String id;
  final String labelKey;
  final List<String> keywords;
  final IconData icon;
  final Color color;

  const QuickActionDef({
    required this.id,
    required this.labelKey,
    required this.keywords,
    required this.icon,
    required this.color,
  });
}

class QuickActionRegistry {
  QuickActionRegistry._();

  static const all = <QuickActionDef>[
    // Library
    QuickActionDef(
      id: 'scan_barcode',
      labelKey: 'quick_scan_barcode',
      keywords: ['scan', 'scanner', 'barcode', 'isbn', 'code-barres'],
      icon: Icons.qr_code_scanner,
      color: Colors.orange,
    ),
    QuickActionDef(
      id: 'search_online',
      labelKey: 'quick_search_online',
      keywords: ['search', 'chercher', 'rechercher', 'online', 'en ligne'],
      icon: Icons.travel_explore,
      color: Colors.blue,
    ),
    QuickActionDef(
      id: 'add_manual',
      labelKey: 'quick_add_manual',
      keywords: ['add', 'ajouter', 'saisir', 'manual', 'manuel'],
      icon: Icons.edit_note,
      color: Colors.green,
    ),
    QuickActionDef(
      id: 'inventory',
      labelKey: 'quick_inventory',
      keywords: ['inventory', 'inventaire', 'inventorier', 'batch', 'shelf'],
      icon: Icons.inventory_2_outlined,
      color: Colors.teal,
    ),
    QuickActionDef(
      id: 'batch_scan',
      labelKey: 'quick_batch_scan',
      keywords: ['batch', 'scan', 'lot', 'multiple'],
      icon: Icons.document_scanner_outlined,
      color: Colors.deepOrange,
    ),

    // Shelves
    QuickActionDef(
      id: 'create_shelf',
      labelKey: 'quick_create_shelf',
      keywords: ['create', 'creer', 'shelf', 'etagere', 'new'],
      icon: Icons.create_new_folder_outlined,
      color: Colors.purple,
    ),
    QuickActionDef(
      id: 'manage_shelves',
      labelKey: 'quick_manage_shelves',
      keywords: ['manage', 'gerer', 'shelves', 'etageres', 'organiser'],
      icon: Icons.edit_note,
      color: Colors.blueGrey,
    ),

    // Import
    QuickActionDef(
      id: 'import_csv',
      labelKey: 'quick_import_csv',
      keywords: ['import', 'csv', 'fichier', 'file'],
      icon: Icons.upload_file,
      color: Colors.indigo,
    ),
    QuickActionDef(
      id: 'import_gleeph',
      labelKey: 'quick_import_gleeph',
      keywords: ['import', 'gleeph', 'migration'],
      icon: Icons.downloading,
      color: Colors.cyan,
    ),
    QuickActionDef(
      id: 'import_goodreads',
      labelKey: 'quick_import_goodreads',
      keywords: ['import', 'goodreads', 'migration'],
      icon: Icons.downloading,
      color: Colors.amber,
    ),

    // Export / Share
    QuickActionDef(
      id: 'share_library',
      labelKey: 'quick_share_library',
      keywords: ['share', 'partager', 'library', 'bibliotheque'],
      icon: Icons.share,
      color: Colors.teal,
    ),

    // Network
    QuickActionDef(
      id: 'my_contacts',
      labelKey: 'quick_my_contacts',
      keywords: ['contacts', 'friends', 'amis', 'network', 'reseau'],
      icon: Icons.people_outline,
      color: Colors.purple,
    ),
  ];

  static QuickActionDef? byId(String id) {
    for (final action in all) {
      if (action.id == id) return action;
    }
    return null;
  }

  static List<QuickActionDef> search(String query) {
    if (query.isEmpty) return List.of(all);
    final lower = query.toLowerCase();
    return all.where((a) {
      if (a.id.contains(lower)) return true;
      for (final kw in a.keywords) {
        if (kw.contains(lower) || lower.contains(kw)) return true;
      }
      return false;
    }).toList();
  }

  static List<QuickActionDef> byIds(List<String> ids) {
    return ids
        .map((id) => byId(id))
        .where((a) => a != null)
        .cast<QuickActionDef>()
        .toList();
  }
}
