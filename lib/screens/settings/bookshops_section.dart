import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/translation_service.dart';
import '../../widgets/my_bookshops_picker.dart';
import '../../widgets/my_libraries_section.dart';
import '../../providers/theme_provider.dart';
import 'settings_scope.dart';

/// Bookshop-linking accordion: the outbound bridges to
/// book-selling websites (independent-bookshop portals on
/// wanted books' pages).
class BookshopsSettingsSection extends StatelessWidget {
  const BookshopsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'settings_bookshops_title',
      'settings_bookshops_show_finder',
      'settings_bookshops_show_finder_desc',
      'settings_bookshops_my_shops',
      'settings_bookshops_search_hint',
      'settings_libraries_title',
      'settings_libraries_add',
      'settings_libraries_show_intro',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('bookshops_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        // Without this the tile's Column centers intrinsic-
        // width children (the library section floated mid-
        // card while everything else hugged the left edge).
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: const Icon(Icons.storefront_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'settings_bookshops_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          SwitchListTile(
            title: Text(
              TranslationService.translate(
                context,
                'settings_bookshops_show_finder',
              ),
            ),
            subtitle: Text(
              TranslationService.translate(
                context,
                'settings_bookshops_show_finder_desc',
              ),
            ),
            value: themeProvider.showBookshopFinder,
            onChanged: (value) => themeProvider.setShowBookshopFinder(value),
          ),
          if (themeProvider.showBookshopFinder) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                      context,
                      'settings_bookshops_my_shops',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const MyBookshopsPicker(),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: MyLibrariesSection(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
