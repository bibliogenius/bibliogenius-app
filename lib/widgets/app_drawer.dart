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
    // debugPrint('Building AppDrawer');
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
            leading: const Icon(Icons.shelves), 
            title: Text(TranslationService.translate(context, 'shelves') ?? 'Shelves'),
            onTap: () {
              Navigator.pop(context);
              context.go('/shelves');
            },
          ),
          // Unified Network screen (contacts + peers merged)
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: Text(TranslationService.translate(context, 'nav_network')),
            onTap: () {
              Navigator.pop(context);
              context.go('/network');
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
          // P2P Connect removed from drawer to simplify UX. Accessed via Network > Add.
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
            leading: const Icon(Icons.insights),
            title: Text(TranslationService.translate(context, 'nav_statistics')),
            onTap: () {
              Navigator.pop(context);
              context.go('/statistics');
            },
          ),
          ListTile(
            leading: const Icon(Icons.school),
            title: Text(TranslationService.translate(context, 'menu_tutorial')),
            onTap: () {
              Navigator.pop(context);
              context.push('/onboarding');
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
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: Text(TranslationService.translate(context, 'nav_report_bug')),
            onTap: () {
              Navigator.pop(context);
              context.push('/feedback');
            },
          ),
        ],
      ),
    );
  }
}
