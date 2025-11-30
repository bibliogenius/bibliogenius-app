import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'BiblioGenius',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Smart Library Manager',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              context.go('/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('My Library'),
            onTap: () {
              Navigator.pop(context);
              context.go('/books');
            },
          ),
          ListTile(
            leading: const Icon(Icons.contacts),
            title: const Text('Contacts'),
            onTap: () {
              Navigator.pop(context);
              context.go('/contacts');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('P2P Connection'),
            onTap: () {
              Navigator.pop(context);
              context.go('/p2p');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('Network Libraries'),
            onTap: () {
              Navigator.pop(context);
              context.go('/peers');
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Borrow Requests'),
            onTap: () {
              Navigator.pop(context);
              context.go('/requests');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('My Profile'),
            onTap: () {
              Navigator.pop(context);
              context.go('/profile');
            },
          ),
        ],
      ),
    );
  }
}
