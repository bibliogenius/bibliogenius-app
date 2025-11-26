import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/api_service.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    }
  }

  Future<void> _deleteContact(int id) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: const Text('Are you sure you want to delete this contact?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
            const SnackBar(content: Text('Contact deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting contact: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _filterType,
            onSelected: (value) {
              setState(() => _filterType = value);
              _loadContacts();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Contacts')),
              const PopupMenuItem(value: 'borrower', child: Text('Borrowers')),
              const PopupMenuItem(value: 'library', child: Text('Libraries')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.contacts, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No contacts yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add your first contact',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
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
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Contact'),
                              content: Text('Delete ${contact.name}?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) => _deleteContact(contact.id!),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: contact.type == 'borrower' ? Colors.blue : Colors.purple,
                            child: Icon(
                              contact.type == 'borrower' ? Icons.person : Icons.library_books,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(contact.name),
                          subtitle: Text(contact.email ?? contact.phone ?? 'No contact info'),
                          trailing: Icon(
                            contact.isActive ? Icons.check_circle : Icons.cancel,
                            color: contact.isActive ? Colors.green : Colors.grey,
                          ),
                          onTap: () {
                            context.push('/contacts/${contact.id}', extra: contact);
                          },
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
