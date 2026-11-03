import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/translation_service.dart';
import '../../widgets/my_bookshops_picker.dart';
import '../../widgets/my_libraries_section.dart';
import '../../providers/theme_provider.dart';
import 'settings_scope.dart';

/// Bookshops and libraries: the outbound bridges to book-selling websites
/// (independent-bookshop portals on wanted books' pages) and the libraries
/// the reader uses. Shown inside the "Find books" section.
class BookshopsSettings extends StatelessWidget {
  const BookshopsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, bookshopsSearchKeys)) {
      return const SizedBox.shrink();
    }
    return Column(
      // Without this the Column centers intrinsic-width children (the
      // library section floated mid-card while everything else hugged the
      // left edge).
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Semantics(
            header: true,
            child: Text(
              TranslationService.translate(context, 'settings_bookshops_title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
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
    );
  }
}

/// Keys whose labels make a search surface the bookshops block; the section
/// title shows the whole section.
const bookshopsSearchKeys = [
  'settings_find_books_title',
  'settings_bookshops_title',
  'settings_bookshops_show_finder',
  'settings_bookshops_show_finder_desc',
  'settings_bookshops_my_shops',
  'settings_bookshops_search_hint',
  'settings_libraries_title',
  'settings_libraries_add',
  'settings_libraries_show_intro',
];
