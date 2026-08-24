import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/contact_card.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/contact_links.dart';

/// Contact affordances for a followed library (ADR-067).
///
/// Only channels that can actually open are offered: a malformed address hides
/// the mail entry, a national number hides WhatsApp. Copying is always offered
/// because it is the fallback that never fails.

/// Builds the subject of the prefilled message.
///
/// The message leaves the app into a third-party client, so it carries the
/// book, and about the recipient it carries nothing: no node id, no relay URL,
/// no mailbox id, not even their library name (ADR-067 D7). The SENDER's own
/// library name is another matter, and is appended as a signature by
/// [contactMessageBody].
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
///
/// [short] picks the one-line version used for text messages, where the
/// letter-shaped version would arrive as three SMS segments.
String contactMessageBody(
  BuildContext context, {
  String? bookTitle,
  String? bookAuthor,
  bool short = false,
  bool reciprocal = false,
}) {
  final hasBook = bookTitle != null && bookTitle.isNotEmpty;
  String text;
  if (short) {
    text = hasBook
        ? TranslationService.translate(
            context,
            'contact_message_short',
            params: {'title': bookTitle},
          )
        : TranslationService.translate(context, 'contact_message_short_plain');
  } else if (!hasBook) {
    text = TranslationService.translate(context, 'contact_message_body_plain');
  } else if (bookAuthor == null || bookAuthor.isEmpty) {
    text = TranslationService.translate(
      context,
      'contact_message_body',
      params: {'title': bookTitle},
    );
  } else {
    text = TranslationService.translate(
      context,
      'contact_message_body_with_author',
      params: {'title': bookTitle, 'author': bookAuthor},
    );
  }
  if (short) {
    final signature = _senderSignature(context);
    return signature == null ? text : '$text\n$signature';
  }

  // Between paired libraries a loan is an exchange, so the message says so.
  // A public directory library is not necessarily in that relationship, and
  // offering it a swap it never signed up for reads as presumptuous.
  if (reciprocal) {
    text =
        '$text\n\n'
        '${TranslationService.translate(context, 'contact_message_reciprocity')}';
  }
  text =
      '$text\n\n'
      '${TranslationService.translate(context, 'contact_message_closing')}';
  final signature = _senderSignature(context);
  return signature == null ? text : '$text\n$signature';
}

/// The sender's library name, when it is one they chose.
///
/// A recipient sees an address, not a person: without this they have to guess
/// which of their approved followers is writing. The default name is never
/// signed, since "My library" identifies nobody.
String? _senderSignature(BuildContext context) {
  final theme = context.read<ThemeProvider>();
  if (!theme.libraryNameCustomized) return null;
  final name = theme.libraryName.trim();
  return name.isEmpty ? null : name;
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
  bool reciprocal = false,
}) {
  final subject = contactMessageSubject(context, bookTitle: bookTitle);
  final body = contactMessageBody(
    context,
    bookTitle: bookTitle,
    bookAuthor: bookAuthor,
    reciprocal: reciprocal,
  );
  // A text message is not a letter: same request, one line.
  final shortBody = contactMessageBody(
    context,
    bookTitle: bookTitle,
    bookAuthor: bookAuthor,
    short: true,
  );

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final whatsAppUri = ContactLinks.whatsApp(card: card, text: shortBody);
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
                    ContactLinks.sms(phone: card.phone, body: shortBody),
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

  /// Whether this library is one we exchange with (a paired peer).
  final bool reciprocal;

  /// Named in the screen-reader label, since a reader who focuses the button
  /// directly would otherwise hear "Contact" with no idea whom.
  final String libraryName;

  const ContactHeaderButton({
    super.key,
    required this.card,
    required this.libraryName,
    this.reciprocal = false,
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
          onPressed: () => showContactActionsSheet(
            context,
            card: card,
            reciprocal: reciprocal,
          ),
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
