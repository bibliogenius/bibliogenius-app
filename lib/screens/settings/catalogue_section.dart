import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/translation_service.dart';
import '../../utils/cover_camera_helper.dart';
import '../../utils/import_actions.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Catalogue accordion: what goes into the library and how it is kept tidy
/// (file import, shelves, duplicates, formats, cover photos).
class CatalogueSettingsSection extends StatefulWidget {
  const CatalogueSettingsSection({super.key});

  @override
  State<CatalogueSettingsSection> createState() =>
      _CatalogueSettingsSectionState();
}

class _CatalogueSettingsSectionState extends State<CatalogueSettingsSection> {
  // Resolved asynchronously: on Android it depends on Play services.
  bool _coverScannerAvailable = false;

  @override
  void initState() {
    super.initState();
    CoverCameraHelper.isDocumentScannerAvailable().then((available) {
      if (mounted && available) {
        setState(() => _coverScannerAvailable = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    // On Android the crop comes from Google Play services, which the
    // description says.
    final autoCropDescKey = io.Platform.isAndroid
        ? 'module_cover_auto_crop_desc_android'
        : 'module_cover_auto_crop_desc';
    if (!settingsMatches(context, [
      'content',
      'migration_card_csv_title',
      'migration_card_shelves_title',
      'duplicates_title',
      'duplicates_settings_subtitle',
      'module_digital_formats',
      'module_digital_formats_desc',
      // Only where the toggle shows, with the description it shows.
      if (_coverScannerAvailable) ...[
        'module_cover_auto_crop',
        autoCropDescKey,
      ],
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsAccordion(
      name: 'catalogue',
      icon: Icons.inventory_2_outlined,
      titleKey: 'content',
      children: [
        ListTile(
          leading: Icon(Icons.import_contacts, color: Colors.orange.shade400),
          title: Text(
            TranslationService.translate(context, 'migration_card_csv_title'),
          ),
          subtitle: Text(
            TranslationService.translate(
              context,
              'migration_card_csv_subtitle',
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => ImportActions.importCsv(context),
        ),
        ListTile(
          leading: Icon(Icons.folder_special, color: Colors.blue.shade400),
          title: Text(
            TranslationService.translate(
              context,
              'migration_card_shelves_title',
            ),
          ),
          subtitle: Text(
            TranslationService.translate(
              context,
              'migration_card_shelves_subtitle',
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/shelves-management'),
        ),
        const DuplicateBooksTile(),
        const SizedBox(height: 8),
        SettingsToggleCard(
          titleKey: 'module_digital_formats',
          descKey: 'module_digital_formats_desc',
          icon: Icons.tablet_mac,
          value: themeProvider.digitalFormatsEnabled,
          onChanged: (value) => themeProvider.setDigitalFormatsEnabled(value),
          helpTopicId: 'digital_formats',
        ),
        if (_coverScannerAvailable)
          SettingsToggleCard(
            titleKey: 'module_cover_auto_crop',
            descKey: autoCropDescKey,
            icon: Icons.crop,
            value: themeProvider.coverAutoCropEnabled,
            onChanged: (value) => themeProvider.setCoverAutoCropEnabled(value),
          ),
      ],
    );
  }
}

/// Tile pointing to the duplicate-book merge (ADR-070).
///
/// Duplicates are what a reader notices after two devices join one account,
/// and the banner on the account screen is the entry point for that case; but
/// the merge itself needs no account, and a library that got its duplicates
/// from a restore rather than a sync would otherwise have no way in at all.
class DuplicateBooksTile extends StatelessWidget {
  const DuplicateBooksTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.copy_all_outlined),
      title: Text(TranslationService.translate(context, 'duplicates_title')),
      subtitle: Text(
        TranslationService.translate(context, 'duplicates_settings_subtitle'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/duplicate-books'),
    );
  }
}
