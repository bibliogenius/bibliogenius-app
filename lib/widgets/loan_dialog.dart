import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/repositories/contact_repository.dart';
import '../models/loan_recipient.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

class LoanDialog extends StatefulWidget {
  const LoanDialog({super.key});

  @override
  State<LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<LoanDialog> {
  List<LoanRecipient> _recipients = [];
  LoanRecipient? _selectedRecipient;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecipients();
  }

  Future<void> _fetchRecipients() async {
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    final List<LoanRecipient> combined = [];

    // 1. Fetch borrower contacts (always works -- same as before)
    try {
      final contacts = await contactRepo.getContacts(type: 'borrower');
      combined.addAll(contacts.map(ContactRecipient.new));
    } catch (e) {
      debugPrint('Failed to fetch borrower contacts: $e');
    }

    // 2. Fetch connected peers (best-effort, may fail if server not ready)
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.getPeers();
      if (response.statusCode == 200) {
        final List<dynamic> peers = response.data['data'] ?? [];
        for (final p in peers) {
          if (p['connection_status'] == 'accepted') {
            combined.add(
              PeerRecipient(
                peerId: p['id'] as int,
                name: (p['name'] ?? '') as String,
                peerDisplayName: p['display_name'] as String?,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch peers for loan dialog: $e');
    }

    if (mounted) {
      setState(() {
        _recipients = combined;
        _isLoading = false;
      });
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
          : _recipients.isEmpty
              ? Text(
                  TranslationService.translate(context, 'no_borrowers_found'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'select_contact_lend',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<LoanRecipient>(
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: TranslationService.translate(
                          context,
                          'filter_borrowers',
                        ),
                      ),
                      items: _recipients.map((recipient) {
                        final icon = switch (recipient) {
                          ContactRecipient() => Icons.person,
                          PeerRecipient() => Icons.devices,
                        };
                        return DropdownMenuItem<LoanRecipient>(
                          value: recipient,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 20),
                              const SizedBox(width: 8),
                              Text(recipient.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedRecipient = value;
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
          onPressed: _selectedRecipient == null
              ? null
              : () => Navigator.pop(context, _selectedRecipient),
          child: Text(TranslationService.translate(context, 'lend_btn')),
        ),
      ],
    );
  }
}
