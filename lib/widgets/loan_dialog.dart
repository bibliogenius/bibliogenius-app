import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
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
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final response = await api.getContacts(type: 'borrower');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['contacts'];
        if (mounted) {
          setState(() {
            _contacts = data.map((json) => Contact.fromJson(json)).toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_loading_contacts')}: $e')),
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
                    Text(TranslationService.translate(context, 'select_contact_lend')),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Contact>(
                      value: _selectedContact,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: TranslationService.translate(context, 'filter_borrowers'),
                      ),
                      items: _contacts.map((contact) {
                        return DropdownMenuItem(
                          value: contact,
                          child: Text(contact.name),
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
