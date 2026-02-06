import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/contact_repository.dart';
import '../services/auth_service.dart';
import '../services/translation_service.dart';
import '../models/contact.dart';

class AddContactScreen extends StatefulWidget {
  final Contact? contact;

  const AddContactScreen({super.key, this.contact});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();

  String _type = 'borrower';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _streetAddressController =
      TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.contact != null) {
      _type = widget.contact!.type;
      _nameController.text = widget.contact!.name;
      _firstNameController.text = widget.contact!.firstName ?? '';
      _emailController.text = widget.contact!.email ?? '';
      _phoneController.text = widget.contact!.phone ?? '';
      _streetAddressController.text =
          widget.contact!.streetAddress ?? widget.contact!.address ?? '';
      _postalCodeController.text = widget.contact!.postalCode ?? '';
      _cityController.text = widget.contact!.city ?? '';
      _countryController.text = widget.contact!.country ?? '';
      _notesController.text = widget.contact!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _firstNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetAddressController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    // Added name validation as per instruction
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'contact_name_required'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final contactRepo = Provider.of<ContactRepository>(context, listen: false);
      final libraryId = await authService.getLibraryId() ?? 1;
      final userId = await authService.getUserId();

      final contactData = {
        'type': _type,
        'name': _nameController.text,
        'first_name': _firstNameController.text.isNotEmpty
            ? _firstNameController.text
            : null,
        'email': _emailController.text.isNotEmpty
            ? _emailController.text
            : null,
        'phone': _phoneController.text.isNotEmpty
            ? _phoneController.text
            : null,
        'street_address': _streetAddressController.text.isNotEmpty
            ? _streetAddressController.text
            : null,
        'postal_code': _postalCodeController.text.isNotEmpty
            ? _postalCodeController.text
            : null,
        'city': _cityController.text.isNotEmpty ? _cityController.text : null,
        'country': _countryController.text.isNotEmpty
            ? _countryController.text
            : null,
        'notes': _notesController.text.isNotEmpty
            ? _notesController.text
            : null,
        'user_id': userId,
        'library_owner_id': libraryId,
        'is_active': true,
      };

      if (widget.contact != null) {
        await contactRepo.updateContact(widget.contact!.id!, contactData);
      } else {
        await contactRepo.createContact(contactData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                widget.contact != null ? 'contact_updated' : 'contact_created',
              ),
            ),
          ),
        );
        context.pop(true); // Return true to indicate refresh needed
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_creating_contact')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.contact != null
              ? TranslationService.translate(context, 'edit_contact_title')
              : TranslationService.translate(context, 'add_contact_title'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          Theme.of(context).appBarTheme.foregroundColor ??
                          Colors.white,
                    ),
                  )
                : TextButton(
                    onPressed: _saveContact,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      foregroundColor:
                          Theme.of(context).appBarTheme.foregroundColor ??
                          Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      widget.contact != null
                          ? (TranslationService.translate(
                                  context,
                                  'update_contact',
                                ) ??
                                'Update')
                          : (TranslationService.translate(
                                  context,
                                  'save_contact',
                                ) ??
                                'Save'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: TranslationService.translate(
                  context,
                  'contact_type_label',
                ),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'borrower',
                  child: Text(
                    TranslationService.translate(context, 'role_borrower'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'library',
                  child: Text(
                    TranslationService.translate(context, 'role_library'),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _type = value!);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(
                  context,
                  'contact_name_label',
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return TranslationService.translate(
                    context,
                    'contact_name_required',
                  );
                }
                return null;
              },
            ),
            // First name field - only shown for borrower type
            if (_type == 'borrower') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _firstNameController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'contact_first_name_label',
                  ),
                  hintText: TranslationService.translate(
                    context,
                    'contact_first_name_hint',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(
                  context,
                  'contact_email_label',
                ),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!value.contains('@')) {
                    return TranslationService.translate(
                      context,
                      'contact_email_invalid',
                    );
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(
                  context,
                  'contact_phone_label',
                ),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            // Street Address
            TextFormField(
              controller: _streetAddressController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(
                      context,
                      'street_address_label',
                    ) ??
                    'Street Address',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Postal Code and City in a row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _postalCodeController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'postal_code_label',
                          ) ??
                          'Postal Code',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _cityController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(context, 'city_label') ??
                          'City',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Country
            TextFormField(
              controller: _countryController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'country_label') ??
                    'Country',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(
                  context,
                  'contact_notes_label',
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            // Save button moved to AppBar
          ],
        ),
      ),
    );
  }
}
