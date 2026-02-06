import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../data/repositories/contact_repository.dart';
import '../services/translation_service.dart';

class LoanDialog extends StatefulWidget {
  const LoanDialog({super.key});

  @override
  State<LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<LoanDialog> {
  List<Contact> _contacts = [];
  Contact? _selectedContact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    try {
      final contacts = await contactRepo.getContacts(type: 'borrower');
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_loading_contacts')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(TranslationService.translate(context, 'lend_book_title')),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : _contacts.isEmpty
          ? Text(TranslationService.translate(context, 'no_borrowers_found'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  TranslationService.translate(context, 'select_contact_lend'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Contact>(
                  initialValue: _selectedContact,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: TranslationService.translate(
                      context,
                      'filter_borrowers',
                    ),
                  ),
                  items: _contacts.map((contact) {
                    return DropdownMenuItem(
                      value: contact,
                      child: Text(contact.fullName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedContact = value;
                    });
                  },
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(TranslationService.translate(context, 'cancel')),
        ),
        ElevatedButton(
          onPressed: _selectedContact == null
              ? null
              : () => Navigator.pop(context, _selectedContact),
          child: Text(TranslationService.translate(context, 'lend_btn')),
        ),
      ],
    );
  }
}
