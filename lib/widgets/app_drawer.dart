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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6BB0A9), Color(0xFF5C8C9F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
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
            leading: const Icon(Icons.book),
            title: Text(
              TranslationService.translate(context, 'nav_my_library'),
            ),
            onTap: () {
              Navigator.pop(context);
              context.go('/books');
            },
          ),

          // Unified Network screen (contacts + peers merged)
          ListTile(
            leading: const Icon(Icons.people),
            title: Text(TranslationService.translate(context, 'nav_network')),
            onTap: () {
              Navigator.pop(context);
              context.go('/network');
            },
          ),

          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(TranslationService.translate(context, 'nav_loans')),
            onTap: () {
              Navigator.pop(context);
              context.go('/network?tab=lent');
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
            leading: const Icon(Icons.dashboard),
            title: Text(TranslationService.translate(context, 'nav_dashboard')),
            onTap: () {
              Navigator.pop(context);
              context.go('/dashboard');
            },
          ),

          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(TranslationService.translate(context, 'nav_settings')),
            onTap: () {
              Navigator.pop(context);
              context.go('/settings');
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
          // TODO: Move "Signaler un bug" to Settings after testing phase
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: Text(
              TranslationService.translate(context, 'nav_report_bug'),
            ),
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
