import 'package:flutter/material.dart';

import '../../widgets/contact_audience_fields.dart';
import '../../widgets/contact_card_fields.dart';
import '../../services/translation_service.dart';
import 'settings_scope.dart';

/// My contact details: a library attribute, shown whatever the
/// directory switch says. Paired libraries receive it through
/// the silent unlisted registration (ADR-053), so it must be
/// editable without ever touching the directory.
class ContactDetailsSettingsSection extends StatelessWidget {
  const ContactDetailsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [
      'my_contact_details_title',
      'hub_contact_email_label',
      'hub_contact_phone_label',
      'contact_audience_title',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('contact_details_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.contact_mail_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'my_contact_details_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              TranslationService.translate(context, 'my_contact_details_intro'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const ContactCardFields(showEncryptedNotice: false),
          const ContactAudienceFields(),
        ],
      ),
    );
  }
}
