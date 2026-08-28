import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/bookshop_portals.dart';
import 'library_portal_wizard.dart';

/// The "My bookshops" picker: the reader's ordered portal selection, fed
/// by an autocomplete over the curated registry. Exclusion is structural:
/// only registry entries can be found. Empty selection = country defaults.
///
/// Shared between the settings accordion and the live-configure sheet
/// opened from the book page's bookshop card.
class MyBookshopsPicker extends StatefulWidget {
  const MyBookshopsPicker({super.key});

  @override
  State<MyBookshopsPicker> createState() => _MyBookshopsPickerState();
}

class _MyBookshopsPickerState extends State<MyBookshopsPicker> {
  TextEditingController? _searchController;

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final themeProvider = context.watch<ThemeProvider>();
    final selectedIds = themeProvider.myBookshopIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t('settings_bookshops_default_note'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final id in selectedIds)
          if (bookshopPortalById(id) case final BookshopPortal portal)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.storefront_outlined, size: 20),
              title: Text(portal.name),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: t('settings_bookshops_remove'),
                onPressed: () => themeProvider.removeMyBookshop(portal.id),
              ),
            ),
        const SizedBox(height: 8),
        Autocomplete<BookshopPortal>(
          displayStringForOption: (portal) => portal.name,
          optionsBuilder: (textEditingValue) {
            return searchBookshopPortals(
              textEditingValue.text,
            ).where((portal) => !selectedIds.contains(portal.id));
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            _searchController = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: t('settings_bookshops_search_hint'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            );
          },
          onSelected: (portal) {
            context.read<ThemeProvider>().addMyBookshop(portal.id);
            _searchController?.clear();
          },
        ),
        for (final custom in themeProvider.myCustomBookshops)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.storefront_outlined, size: 20),
            title: Text(custom.name),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: t('settings_bookshops_remove'),
              onPressed: () =>
                  themeProvider.removeMyCustomBookshop(custom.urlTemplate),
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(t('settings_bookshops_add_custom')),
          onPressed: () => LibraryPortalWizard.show(
            context,
            kind: PortalWizardKind.bookshop,
          ),
        ),
      ],
    );
  }
}
