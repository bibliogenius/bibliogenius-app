import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../services/translation_service.dart';
import '../utils/library_portals.dart';

/// Longest lender name accepted from the free-text field.
const int lenderPlaceNameMaxLength = 100;

/// Contacts who own the book first, then alphabetically within each group.
List<Contact> sortContactsForLender(List<Contact> contacts) {
  return [...contacts]..sort((a, b) {
    final aHas = a.hasBook == true;
    final bHas = b.hasBook == true;
    if (aHas != bHas) return aHas ? -1 : 1;
    return a.displayName.compareTo(b.displayName);
  });
}

/// Asks who lent the book and returns the lender's display name, or null
/// when the user cancels.
///
/// The lender can be a connected library, an existing contact, a contact
/// created on the spot through [createContact], or a place typed by hand.
/// Libraries and places never become contacts: only the name is kept, on the
/// borrowed copy (ADR-034).
///
/// Cancelling [createContact] or the free-text dialog brings the picker back.
Future<String?> pickLenderName(
  BuildContext context, {
  required List<LocalLibraryPortal> portals,
  required List<Contact> contacts,
  required Future<Contact?> Function() createContact,
}) async {
  final sorted = sortContactsForLender(contacts);
  while (true) {
    if (!context.mounted) return null;
    final choice = await showDialog<_LenderChoice>(
      context: context,
      builder: (_) => _LenderPickerDialog(portals: portals, contacts: sorted),
    );
    if (choice == null || !context.mounted) return null;
    switch (choice) {
      case _LenderNamed(:final name):
        return name;
      case _LenderNewContact():
        final created = await createContact();
        if (created != null) return created.fullName;
      case _LenderPlace():
        final name = await showDialog<String>(
          context: context,
          builder: (_) => const _PlaceNameDialog(),
        );
        if (name != null) return name;
    }
  }
}

/// Optional due date step. Returns `yyyy-MM-dd`, or null when skipped.
///
/// The wording stays factual: nothing reminds the user of this date.
Future<String?> pickBorrowDueDate(BuildContext context) async {
  final today = DateUtils.dateOnly(DateTime.now());
  final picked = await showDatePicker(
    context: context,
    initialDate: today.add(const Duration(days: 21)),
    firstDate: DateTime(today.year - 1),
    lastDate: DateTime(today.year + 2, 12, 31),
    helpText: TranslationService.translate(context, 'borrow_due_date_title'),
    cancelText: TranslationService.translate(context, 'borrow_due_date_skip'),
  );
  if (picked == null) return null;
  return picked.toIso8601String().split('T')[0];
}

sealed class _LenderChoice {
  const _LenderChoice();
}

class _LenderNamed extends _LenderChoice {
  final String name;
  const _LenderNamed(this.name);
}

class _LenderNewContact extends _LenderChoice {
  const _LenderNewContact();
}

class _LenderPlace extends _LenderChoice {
  const _LenderPlace();
}

class _LenderPickerDialog extends StatelessWidget {
  final List<LocalLibraryPortal> portals;
  final List<Contact> contacts;

  const _LenderPickerDialog({required this.portals, required this.contacts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String t(String key) => TranslationService.translate(context, key);

    return AlertDialog(
      title: Text(t('select_lender')),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (portals.isNotEmpty) ...[
              _SectionHeader(t('lender_section_libraries')),
              for (final portal in portals)
                ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: Text(portal.name),
                  onTap: () =>
                      Navigator.pop(context, _LenderNamed(portal.name)),
                ),
            ],
            if (contacts.isNotEmpty) ...[
              _SectionHeader(t('contacts')),
              for (final contact in contacts)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(contact.displayName),
                  subtitle: contact.hasBook == true
                      ? Text(
                          t('contact_has_book'),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  onTap: () =>
                      Navigator.pop(context, _LenderNamed(contact.fullName)),
                ),
            ],
            if (portals.isNotEmpty || contacts.isNotEmpty) const Divider(),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(t('lender_new_contact')),
              onTap: () => Navigator.pop(context, const _LenderNewContact()),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: Text(t('lender_other_place')),
              onTap: () => Navigator.pop(context, const _LenderPlace()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('cancel')),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Semantics(
        header: true,
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}

/// Free-text lender name. Owns its controller so it is disposed with the
/// dialog's last frame, not right after the pop.
class _PlaceNameDialog extends StatefulWidget {
  const _PlaceNameDialog();

  @override
  State<_PlaceNameDialog> createState() => _PlaceNameDialogState();
}

class _PlaceNameDialogState extends State<_PlaceNameDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);

    return AlertDialog(
      title: Text(t('lender_other_place')),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: lenderPlaceNameMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: t('lender_place_name_label'),
            hintText: t('lender_place_name_hint'),
          ),
          validator: (value) => (value ?? '').trim().isEmpty
              ? t('lender_place_name_required')
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('cancel')),
        ),
        TextButton(onPressed: _submit, child: Text(t('confirm'))),
      ],
    );
  }
}
