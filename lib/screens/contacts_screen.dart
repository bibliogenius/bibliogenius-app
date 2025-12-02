import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  bool _isLoading = true;
  String _filterType = 'all'; // 'all', 'borrower', 'library'

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      final response = await apiService.getContacts(
        libraryId: 1, // TODO: Get from auth context
        type: _filterType == 'all' ? null : _filterType,
      );
      final List<dynamic> contactsJson = response.data['contacts'];
      setState(() {
        _contacts = contactsJson.map((json) => Contact.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${TranslationService.translate(context, 'error_loading_contacts')}: $e')));
      }
    }
  }

  Future<void> _deleteContact(int id) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete_contact_title')),
        content: Text(TranslationService.translate(context, 'delete_contact_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(TranslationService.translate(context, 'delete_contact_btn'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await apiService.deleteContact(id);
        _loadContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(TranslationService.translate(context, 'contact_deleted'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${TranslationService.translate(context, 'error_deleting_contact')}: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isPro = themeProvider.isLibrarian;
    final title = isPro ? 'Emprunteurs' : 'Mes Contacts';
    final emptyTitle = isPro ? 'Aucun emprunteur' : 'Vos Contacts';
    final emptySubtitle = isPro 
        ? 'Gérez ici les personnes qui empruntent vos livres.'
        : 'Ajoutez vos contacts pour noter quand vous leur prêtez un livre.';

    return Scaffold(
      appBar: GenieAppBar(
        title: title,
        actions: [
          PopupMenuButton<String>(
            initialValue: _filterType,
            onSelected: (value) {
              setState(() => _filterType = value);
              _loadContacts();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'all', child: Text(TranslationService.translate(context, 'filter_all_contacts'))),
              PopupMenuItem(value: 'borrower', child: Text(TranslationService.translate(context, 'filter_borrowers'))),
              PopupMenuItem(value: 'library', child: Text(TranslationService.translate(context, 'filter_libraries'))),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.contacts_outlined,
                          size: 80,
                          color: Theme.of(context).primaryColor.withOpacity(0.3),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          emptyTitle,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          emptySubtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPro 
                            ? 'Appuyez sur + pour ajouter un emprunteur.'
                            : 'Appuyez sur + pour ajouter un contact.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () => context.push('/contacts/add'),
                          icon: const Icon(Icons.person_add),
                          label: Text(isPro ? 'Ajouter un emprunteur' : 'Ajouter un contact'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadContacts,
              child: ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, index) {
                  final contact = _contacts[index];
                  return Dismissible(
                    key: Key('contact-${contact.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete, color: Colors.red),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(TranslationService.translate(context, 'delete_contact_title')),
                          content: Text('${TranslationService.translate(context, 'delete_contact_title')} ${contact.name}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(TranslationService.translate(context, 'cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                TranslationService.translate(context, 'delete_contact_btn'),
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (direction) => _deleteContact(contact.id!),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Theme.of(context).dividerColor.withOpacity(0.1),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: contact.type == 'borrower'
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.purple.withOpacity(0.1),
                          child: Icon(
                            contact.type == 'borrower'
                                ? Icons.person
                                : Icons.library_books,
                            color: contact.type == 'borrower'
                                ? Colors.blue
                                : Colors.purple,
                          ),
                        ),
                        title: Text(
                          contact.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              contact.email ?? contact.phone ?? 'No contact info',
                              style: TextStyle(
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: contact.isActive
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                contact.isActive ? Icons.check_circle : Icons.cancel,
                                size: 14,
                                color: contact.isActive ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                contact.isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: contact.isActive ? Colors.green : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          context.push('/contacts/${contact.id}', extra: contact);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/contacts/add');
          _loadContacts();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
