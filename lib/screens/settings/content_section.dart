import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/translation_service.dart';
import '../../utils/import_actions.dart';
import 'settings_scope.dart';

/// Data Management
/// Content accordion
class ContentSettingsSection extends StatelessWidget {
  const ContentSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [
      'content',
      'migration_card_csv_title',
      'migration_card_shelves_title',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('content_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.inventory_2_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'content'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
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
        ],
      ),
    );
  }
}
