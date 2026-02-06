import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/translation_service.dart';
import '../data/repositories/contact_repository.dart';
import '../providers/theme_provider.dart';
import 'add_contact_screen.dart';
import 'borrow_book_screen.dart';

class ContactDetailsScreen extends StatefulWidget {
  final Contact contact;

  const ContactDetailsScreen({super.key, required this.contact});

  @override
  State<ContactDetailsScreen> createState() => _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends State<ContactDetailsScreen> {
  late Contact _contact;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'contact_details_title') ??
              'Contact Details',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddContactScreen(contact: _contact),
                ),
              );

              if (result == true && mounted) {
                // Refresh contact details
                try {
                  final contactRepo = Provider.of<ContactRepository>(
                    context,
                    listen: false,
                  );
                  final contact = await contactRepo.getContact(_contact.id!);
                  if (mounted) {
                    setState(() {
                      _contact = contact;
                    });
                  }
                } catch (e) {
                  debugPrint('Error refreshing contact: $e');
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: _contact.type == 'borrower'
                  ? Colors.blue
                  : Colors.purple,
              child: Icon(
                _contact.type == 'borrower'
                    ? Icons.person
                    : Icons.library_books,
                size: 50,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _contact.fullName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              if (!Provider.of<ThemeProvider>(context, listen: false).isLibrarian) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _borrowFromContact(context),
                    icon: const Icon(Icons.book_outlined),
                    label: Text(
                      TranslationService.translate(
                            context,
                            'borrow_from_contact',
                          ) ??
                          'Borrow a book',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _lendToContact(context),
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(
                    TranslationService.translate(context, 'lend_to_contact') ??
                        'Lend a book',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildInfoCard(
            context,
            TranslationService.translate(context, 'contact_type_label'),
            _contact.type == 'borrower'
                ? TranslationService.translate(context, 'role_borrower')
                : TranslationService.translate(context, 'role_library'),
          ),
          _buildInfoCard(
            context,
            TranslationService.translate(context, 'contact_name_label'),
            _contact.name,
          ),
          if (_contact.firstName != null && _contact.firstName!.isNotEmpty)
            _buildInfoCard(
              context,
              TranslationService.translate(
                    context,
                    'contact_first_name_label',
                  ) ??
                  'First Name',
              _contact.firstName!,
            ),
          if (_contact.email != null)
            _buildInfoCard(
              context,
              TranslationService.translate(context, 'contact_email_label'),
              _contact.email!,
            ),
          if (_contact.phone != null)
            _buildInfoCard(
              context,
              TranslationService.translate(context, 'contact_phone_label'),
              _contact.phone!,
            ),
          if (_contact.formattedAddress.isNotEmpty)
            _buildInfoCard(
              context,
              TranslationService.translate(context, 'contact_address_label'),
              _contact.formattedAddress,
            ),
          if (_contact.notes != null)
            _buildInfoCard(
              context,
              TranslationService.translate(context, 'contact_notes_label'),
              _contact.notes!,
            ),
          _buildInfoCard(
            context,
            TranslationService.translate(context, 'status_label'),
            _contact.isActive
                ? TranslationService.translate(context, 'status_active')
                : TranslationService.translate(context, 'status_inactive'),
            valueColor: _contact.isActive ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, color: valueColor)),
          ],
        ),
      ),
    );
  }

  Future<void> _borrowFromContact(BuildContext context) async {
    // Navigate to the borrow book screen
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => BorrowBookScreen(contact: _contact),
      ),
    );

    // Refresh if a book was borrowed
    if (result == true && mounted) {
      setState(() {}); // Trigger rebuild to show updated loans
    }
  }

  Future<void> _lendToContact(BuildContext context) async {
    // Navigate to book list to select a book to lend
    context.push('/books?action=select_for_loan&contact_id=${_contact.id}');
  }
}
