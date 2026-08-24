import 'package:flutter/material.dart';
import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';
import 'contact_card_fields.dart';

/// Invitation to fill the contact card, offered where its absence has a
/// consequence: the contacts tab, once someone actually follows this library
/// (ADR-067 D9).
///
/// Deliberately NOT hooked to the approve button of a follow request. A follow
/// coming from a paired peer is auto-approved without any UI
/// (`reconcilePairedPeerFollows`, ADR-053), so a prompt tied to that gesture
/// would miss the commonest case of all. The trigger is a state: someone
/// follows us, and we gave them nothing to reach us with.

/// Opens the contact card form as a sheet.
///
/// The fields save as they are typed, so the sheet closes on "done" and has
/// nothing to commit.
Future<void> showContactCardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    TranslationService.translate(
                      sheetContext,
                      'contact_prompt_title',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    TranslationService.translate(
                      sheetContext,
                      'contact_prompt_body',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // Said plainly rather than glossed over: an approved follower
                // has already decrypted the card, so unfollowing cannot take
                // it back. A reader who learns that here trusts the rest.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    TranslationService.translate(
                      sheetContext,
                      'contact_prompt_irreversible',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const ContactCardFields(showEncryptedNotice: false),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(
                      TranslationService.translate(sheetContext, 'done'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Dismissible card offering to fill the contact details.
class ContactPromptBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const ContactPromptBanner({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.contact_mail_outlined,
            size: 20,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(context, 'contact_prompt_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TranslationService.translate(
                    context,
                    'contact_prompt_banner_body',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: () => showContactCardSheet(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      TranslationService.translate(
                        context,
                        'contact_prompt_action',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: cs.onSecondaryContainer,
            tooltip: TranslationService.translate(context, 'close'),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Whether the invitation should be offered at all.
///
/// Cheap checks first: the card being empty is local state, so the follower
/// list is only fetched for the users who have not filled it in.
bool shouldOfferContactPrompt(HubDirectoryProvider provider) {
  if (!provider.isHubEnabled || !provider.isRegistered) return false;
  if (provider.contactCard.isNotEmpty) return false;
  return provider.followers.any((f) => f.isActive);
}
