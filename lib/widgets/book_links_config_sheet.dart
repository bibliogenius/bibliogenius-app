import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import 'my_bookshops_picker.dart';
import 'my_libraries_section.dart';

/// Live-configuration sheet for the book page's outbound-link cards:
/// bookshop portals AND the connected library, so either card's gear
/// gives access to both (in particular, the library wizard is reachable
/// before any library card exists to carry a gear).
Future<void> showBookLinksConfigSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(
                  sheetContext,
                  'settings_bookshops_my_shops',
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            // One switch per block, on both sides: the library section
            // already carried its own, the bookshops had theirs in the
            // settings screen only.
            Consumer<ThemeProvider>(
              builder: (context, theme, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  TranslationService.translate(
                    sheetContext,
                    'settings_bookshops_show_finder',
                  ),
                ),
                subtitle: Text(
                  TranslationService.translate(
                    sheetContext,
                    'settings_bookshops_show_finder_desc',
                  ),
                ),
                value: theme.showBookshopFinder,
                onChanged: theme.setShowBookshopFinder,
              ),
            ),
            const MyBookshopsPicker(),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const MyLibrariesSection(),
          ],
        ),
      ),
    ),
  );
}
