import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import 'library_portal_wizard.dart';

/// "My library" section: the catalogues connected through the wizard,
/// with removal and the wizard entry point. Shared between the settings
/// accordion and the book page's configuration sheet.
class MyLibrariesSection extends StatelessWidget {
  const MyLibrariesSection({super.key});

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final themeProvider = context.watch<ThemeProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('settings_libraries_title'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(t('settings_libraries_show_intro')),
          subtitle: Text(t('settings_libraries_show_intro_desc')),
          value: themeProvider.showLibraryLinks,
          onChanged: (value) => themeProvider.setShowLibraryLinks(value),
        ),
        if (themeProvider.myLibraryPortals.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // Same pitch as the book page's intro card: one message,
              // both surfaces.
              t('library_intro_text'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final portal in themeProvider.myLibraryPortals)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.local_library_outlined, size: 20),
            title: Text(portal.name),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: t('settings_bookshops_remove'),
              onPressed: () =>
                  themeProvider.removeMyLibraryPortal(portal.urlTemplate),
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(t('settings_libraries_add')),
          onPressed: () => LibraryPortalWizard.show(context),
        ),
      ],
    );
  }
}
