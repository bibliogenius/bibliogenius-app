import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();

  String _type = 'borrower';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() => _isSaving = true);

    try {
      final contactData = {
        'type': _type,
        'name': _nameController.text,
        'email': _emailController.text.isEmpty ? null : _emailController.text,
        'phone': _phoneController.text.isEmpty ? null : _phoneController.text,
        'address': _addressController.text.isEmpty
            ? null
            : _addressController.text,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'library_owner_id': 1, // TODO: Get from auth context
        'is_active': true,
      };

      await apiService.createContact(contactData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'contact_created'))),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${TranslationService.translate(context, 'error_creating_contact')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(TranslationService.translate(context, 'add_contact_title'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_type_label'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'borrower', child: Text(TranslationService.translate(context, 'role_borrower'))),
                DropdownMenuItem(value: 'library', child: Text(TranslationService.translate(context, 'role_library'))),
              ],
              onChanged: (value) {
                setState(() => _type = value!);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_name_label'),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return TranslationService.translate(context, 'contact_name_required');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_email_label'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!value.contains('@')) {
                    return TranslationService.translate(context, 'contact_email_invalid');
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_phone_label'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_address_label'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'contact_notes_label'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveContact,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(TranslationService.translate(context, 'save_contact')),
            ),
          ],
        ),
      ),
    );
  }
}
