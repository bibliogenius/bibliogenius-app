import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';

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
                  TranslationService.translate(context, 'app_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(context, 'app_subtitle'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: Text(TranslationService.translate(context, 'nav_dashboard')),
            onTap: () {
              Navigator.pop(context);
              context.go('/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: Text(TranslationService.translate(context, 'nav_my_library')),
            onTap: () {
              Navigator.pop(context);
              context.go('/books');
            },
          ),
          ListTile(
            leading: const Icon(Icons.contacts),
            title: Text(TranslationService.translate(context, 'nav_contacts')),
            onTap: () {
              Navigator.pop(context);
              context.go('/contacts');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(TranslationService.translate(context, 'nav_p2p')),
            onTap: () {
              Navigator.pop(context);
              context.go('/p2p');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: Text(TranslationService.translate(context, 'nav_network')),
            onTap: () {
              Navigator.pop(context);
              context.go('/peers');
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(TranslationService.translate(context, 'nav_requests')),
            onTap: () {
              Navigator.pop(context);
              context.go('/requests');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(TranslationService.translate(context, 'nav_profile')),
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
