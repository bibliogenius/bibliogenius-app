import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/contact_card.dart';
import '../services/translation_service.dart';
import '../utils/contact_links.dart';

/// Contact affordances for a followed library (ADR-067).
///
/// Only channels that can actually open are offered: a malformed address hides
/// the mail entry, a national number hides WhatsApp. Copying is always offered
/// because it is the fallback that never fails.

/// Builds the subject of the prefilled message.
///
/// The message leaves the app into a third-party client, so it carries the book
/// and nothing else: no node id, no relay URL, no mailbox id, no library name
/// (ADR-067 D7).
String contactMessageSubject(BuildContext context, {String? bookTitle}) {
  if (bookTitle == null || bookTitle.isEmpty) {
    return TranslationService.translate(
      context,
      'contact_message_subject_plain',
    );
  }
  return TranslationService.translate(
    context,
    'contact_message_subject',
    params: {'title': bookTitle},
  );
}

/// Builds the body of the prefilled message.
String contactMessageBody(
  BuildContext context, {
  String? bookTitle,
  String? bookAuthor,
}) {
  if (bookTitle == null || bookTitle.isEmpty) {
    return TranslationService.translate(context, 'contact_message_body_plain');
  }
  if (bookAuthor == null || bookAuthor.isEmpty) {
    return TranslationService.translate(
      context,
      'contact_message_body',
      params: {'title': bookTitle},
    );
  }
  return TranslationService.translate(
    context,
    'contact_message_body_with_author',
    params: {'title': bookTitle, 'author': bookAuthor},
  );
}

/// Opens [uri] in its external application, reporting failure instead of
/// swallowing it.
Future<void> launchContactUri(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final failure = TranslationService.translate(
    context,
    'contact_launch_failed',
  );
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// Copies the whole card to the clipboard.
Future<void> copyContactCard(BuildContext context, ContactCard card) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = TranslationService.translate(context, 'contact_copied');
  await Clipboard.setData(
    ClipboardData(text: ContactLinks.clipboardText(card)),
  );
  messenger.showSnackBar(SnackBar(content: Text(copied)));
}

/// Copies a single field.
Future<void> copyContactValue(BuildContext context, String value) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = TranslationService.translate(context, 'contact_copied');
  await Clipboard.setData(ClipboardData(text: value));
  messenger.showSnackBar(SnackBar(content: Text(copied)));
}

/// Shows the channel picker for [card], prefilled with the book context when
/// there is one.
Future<void> showContactActionsSheet(
  BuildContext context, {
  required ContactCard card,
  String? bookTitle,
  String? bookAuthor,
}) {
  final subject = contactMessageSubject(context, bookTitle: bookTitle);
  final body = contactMessageBody(
    context,
    bookTitle: bookTitle,
    bookAuthor: bookAuthor,
  );

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final whatsAppUri = ContactLinks.whatsApp(card: card, text: body);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                TranslationService.translate(
                  sheetContext,
                  'contact_sheet_title',
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (card.canSendEmail)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(
                  TranslationService.translate(
                    sheetContext,
                    'contact_action_email',
                  ),
                ),
                subtitle: Text(card.email),
                onTap: () {
                  Navigator.pop(sheetContext);
                  launchContactUri(
                    context,
                    ContactLinks.mailto(
                      email: card.email,
                      subject: subject,
                      body: body,
                    ),
                  );
                },
              ),
            if (whatsAppUri != null)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(
                  TranslationService.translate(
                    sheetContext,
                    'contact_action_whatsapp',
                  ),
                ),
                subtitle: Text(card.phone),
                onTap: () {
                  Navigator.pop(sheetContext);
                  launchContactUri(context, whatsAppUri);
                },
              ),
            if (card.canSendMessage)
              ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(
                  TranslationService.translate(
                    sheetContext,
                    'contact_action_sms',
                  ),
                ),
                subtitle: Text(card.phone),
                onTap: () {
                  Navigator.pop(sheetContext);
                  launchContactUri(
                    context,
                    ContactLinks.sms(phone: card.phone, body: body),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(
                TranslationService.translate(
                  sheetContext,
                  'contact_action_copy',
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                copyContactCard(context, card);
              },
            ),
            if (card.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  card.note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// The "Contact" button as it appears in a library's identity header
/// (ADR-067 D5).
///
/// One widget rather than the same twenty lines in the peer screen and in the
/// directory catalogue: they carry the same rule, the same colours and the same
/// screen-reader label, and a copy of each would drift on the first change.
class ContactHeaderButton extends StatelessWidget {
  final ContactCard card;

  /// Named in the screen-reader label, since a reader who focuses the button
  /// directly would otherwise hear "Contact" with no idea whom.
  final String libraryName;

  const ContactHeaderButton({
    super.key,
    required this.card,
    required this.libraryName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label:
            '${TranslationService.translate(context, 'contact_cta')} : $libraryName',
        child: FilledButton.tonal(
          onPressed: () => showContactActionsSheet(context, card: card),
          // On primaryContainer the tonal default sits at the same tone as the
          // card behind it; primary/onPrimary is the one pair the scheme
          // guarantees legible in both themes.
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(TranslationService.translate(context, 'contact_cta')),
        ),
      ),
    );
  }
}
