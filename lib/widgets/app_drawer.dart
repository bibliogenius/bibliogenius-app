import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../services/wizard_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isKid = themeProvider.isKid;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'BiblioGenius', // Use literal or translation
                  style: TextStyle(
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
            title: Text(isKid ? TranslationService.translate(context, 'nav_contacts') : TranslationService.translate(context, 'nav_contacts')), // Could use 'My Friends' for kid
            onTap: () {
              Navigator.pop(context);
              context.go('/contacts');
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
          // Hide P2P Setup for kids, they likely just use the network
          if (!isKid)
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(TranslationService.translate(context, 'nav_p2p_connect')),
            onTap: () {
              Navigator.pop(context);
              context.go('/p2p');
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
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(TranslationService.translate(context, 'nav_help')),
            onTap: () {
              Navigator.pop(context);
              context.go('/help');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Restart Tour'), // Add translation later if needed
            onTap: () async {
              Navigator.pop(context);
              await WizardService.resetWizard();
              if (context.mounted) {
                 // Force reload of dashboard to trigger wizard
                 context.go('/dashboard');
                 // Or we could just call a method if we had access to state, but navigation is easier
              }
            },
          ),
        ],
      ),
    );
  }
}
