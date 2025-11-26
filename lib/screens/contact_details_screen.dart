import 'package:flutter/material.dart';
import '../models/contact.dart';

class ContactDetailsScreen extends StatelessWidget {
  final Contact contact;

  const ContactDetailsScreen({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit feature coming soon')),
              );
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
              backgroundColor: contact.type == 'borrower' ? Colors.blue : Colors.purple,
              child: Icon(
                contact.type == 'borrower' ? Icons.person : Icons.library_books,
                size: 50,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildInfoCard('Type', contact.type.toUpperCase()),
          _buildInfoCard('Name', contact.name),
          if (contact.email != null) _buildInfoCard('Email', contact.email!),
          if (contact.phone != null) _buildInfoCard('Phone', contact.phone!),
          if (contact.address != null) _buildInfoCard('Address', contact.address!),
          if (contact.notes != null) _buildInfoCard('Notes', contact.notes!),
          _buildInfoCard(
            'Status',
            contact.isActive ? 'Active' : 'Inactive',
            valueColor: contact.isActive ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, {Color? valueColor}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
