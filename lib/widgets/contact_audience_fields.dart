import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';

/// Who receives the contact card: paired libraries, directory followers.
///
/// Shared by the "My contact details" settings section and by the prompt
/// offered on the contacts tab, next to [ContactCardFields], so the two forms
/// cannot drift. Each tick is applied at once: the provider re-seals the card
/// for the libraries now included and withdraws it from those now excluded.
class ContactAudienceFields extends StatelessWidget {
  final EdgeInsets padding;

  const ContactAudienceFields({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<HubDirectoryProvider>();
    final audience = provider.contactAudience;
    String t(String key) => TranslationService.translate(context, key);

    final nobody =
        provider.contactCard.isNotEmpty &&
        !audience.pairedPeers &&
        !audience.directoryFollowers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: padding.copyWith(top: 16, bottom: 4),
          child: Semantics(
            header: true,
            child: Text(
              t('contact_audience_title'),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
        // CheckboxListTile merges title, subtitle and checked state into one
        // semantics node, so a screen reader hears who is concerned and
        // whether they are included in a single announcement.
        CheckboxListTile(
          contentPadding: padding,
          secondary: const Icon(Icons.link),
          title: Text(t('contact_audience_paired')),
          subtitle: Text(t('contact_audience_paired_desc')),
          value: audience.pairedPeers,
          onChanged: (v) => provider.setContactAudience(
            audience.copyWith(pairedPeers: v ?? false),
          ),
        ),
        CheckboxListTile(
          contentPadding: padding,
          secondary: const Icon(Icons.explore_outlined),
          title: Text(t('contact_audience_directory')),
          subtitle: Text(t('contact_audience_directory_desc')),
          value: audience.directoryFollowers,
          onChanged: (v) => provider.setContactAudience(
            audience.copyWith(directoryFollowers: v ?? false),
          ),
        ),
        if (nobody)
          Padding(
            padding: padding.copyWith(top: 4),
            // Announced when it appears, so unticking the last box is not a
            // silent dead end for a screen reader user.
            child: Semantics(
              liveRegion: true,
              child: Text(
                t('contact_audience_nobody'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        Padding(
          padding: padding.copyWith(top: 4, bottom: 8),
          child: Text(
            t('contact_audience_withdraw_note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
