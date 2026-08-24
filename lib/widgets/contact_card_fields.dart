import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';

/// The three typed contact fields of ADR-067, in one place.
///
/// Shared by the hub section of the settings and by the prompt offered on the
/// contacts tab: two forms writing the same card would drift, and the one
/// offered in context would end up the poorer of the two.
///
/// Each field writes through to [HubDirectoryProvider] as it is typed; the
/// provider sanitizes, stores, and re-seals for followers after its own
/// debounce. There is no save button to forget.
class ContactCardFields extends StatefulWidget {
  /// Explanatory line above the fields. Shown in the settings, where the
  /// section header does not say who can read the card.
  final bool showEncryptedNotice;

  final EdgeInsets fieldPadding;

  const ContactCardFields({
    super.key,
    this.showEncryptedNotice = true,
    this.fieldPadding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  @override
  State<ContactCardFields> createState() => _ContactCardFieldsState();
}

class _ContactCardFieldsState extends State<ContactCardFields> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _seed();
  }

  /// Loads the stored card and fills the fields once.
  ///
  /// The widget loads what it displays rather than trusting a caller to have
  /// done it: it is mounted from two places, and a form that renders empty
  /// because the read had not landed yet would read as "nothing was ever
  /// saved". Never overwrites a field the user has already typed into, since
  /// the read is asynchronous and can land late.
  Future<void> _seed() async {
    final provider = context.read<HubDirectoryProvider>();
    await provider.loadContactInfo();
    if (!mounted) return;
    final card = provider.contactCard;
    if (_emailController.text.isEmpty) _emailController.text = card.email;
    if (_phoneController.text.isEmpty) _phoneController.text = card.phone;
    if (_noteController.text.isEmpty) _noteController.text = card.note;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<HubDirectoryProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showEncryptedNotice)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.fieldPadding.left,
              16,
              widget.fieldPadding.right,
              4,
            ),
            child: Text(
              TranslationService.translate(
                context,
                'hub_contact_encrypted_notice',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Padding(
          padding: widget.fieldPadding,
          child: TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: TranslationService.translate(
                context,
                'hub_contact_email_label',
              ),
              // RFC 2606 reserved domain: an example that is neither a real
              // address nor a French string.
              hintText: 'name@example.org',
              prefixIcon: const Icon(Icons.alternate_email),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: provider.setContactEmail,
          ),
        ),
        Padding(
          padding: widget.fieldPadding,
          child: TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: TranslationService.translate(
                context,
                'hub_contact_phone_label',
              ),
              hintText: TranslationService.translate(
                context,
                'hub_contact_phone_hint',
              ),
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
              // The international form is required at entry: it is what a
              // WhatsApp link needs, and a national number carries no country
              // to guess from at read time.
              helperText: TranslationService.translate(
                context,
                'hub_contact_phone_helper',
              ),
              helperMaxLines: 2,
            ),
            keyboardType: TextInputType.phone,
            onChanged: provider.setContactPhone,
          ),
        ),
        Padding(
          padding: widget.fieldPadding,
          child: TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: TranslationService.translate(
                context,
                'hub_contact_note_label',
              ),
              hintText: TranslationService.translate(
                context,
                'hub_contact_note_hint',
              ),
              prefixIcon: const Icon(Icons.notes),
              border: const OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
            onChanged: provider.setContactNote,
          ),
        ),
      ],
    );
  }
}
