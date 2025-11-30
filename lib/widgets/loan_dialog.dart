import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/api_service.dart';

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
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lend Book'),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : _contacts.isEmpty
              ? const Text('No borrowers found. Add a contact first.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select a contact to lend this book to:'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Contact>(
                      value: _selectedContact,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Borrower',
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
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedContact == null
              ? null
              : () => Navigator.pop(context, _selectedContact),
          child: const Text('Lend'),
        ),
      ],
    );
  }
}
