import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';
import 'app_drawer.dart';

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width > 600;

    return Scaffold(
      drawer: useRail ? null : const AppDrawer(), // Drawer for mobile
      body: Row(
        children: [
          if (useRail)
            NavigationRail(
              selectedIndex: _calculateSelectedIndex(context),
              onDestinationSelected: (int index) => _onItemTapped(index, context),
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text(TranslationService.translate(context, 'dashboard')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.book),
                  label: Text(TranslationService.translate(context, 'library')),
                ),
                // Unified Network (contacts + peers merged)
                NavigationRailDestination(
                  icon: Icon(Icons.cloud_sync),
                  label: Text(TranslationService.translate(context, 'network')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.swap_horiz),
                  label: Text(TranslationService.translate(context, 'requests')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person),
                  label: Text(TranslationService.translate(context, 'profile')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.insights),
                  label: Text(TranslationService.translate(context, 'nav_statistics')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.school),
                  label: Text(TranslationService.translate(context, 'menu_tutorial')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.help_outline),
                  label: Text(TranslationService.translate(context, 'nav_help')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bug_report),
                  label: Text(TranslationService.translate(context, 'nav_report_bug')),
                ),
              ],
            ),
          if (useRail) const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
      // No bottomNavigationBar
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/books')) return 1;
    if (location.startsWith('/network') || 
        location.startsWith('/contacts') || 
        location.startsWith('/peers')) return 2;
    if (location.startsWith('/requests')) return 3;
    if (location.startsWith('/profile')) return 4;
    if (location.startsWith('/statistics')) return 5;
    if (location.startsWith('/onboarding')) return 6;
    if (location.startsWith('/help')) return 7;
    if (location.startsWith('/feedback')) return 8;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/books');
        break;
      case 2:
        context.go('/network');
        break;
      case 3:
        context.go('/requests');
        break;
      case 4:
        context.go('/profile');
        break;
      case 5:
        context.go('/statistics');
        break;
      case 6:
        context.push('/onboarding');
        break;
      case 7:
        context.go('/help');
        break;
      case 8:
        context.push('/feedback');
        break;
    }
  }
}
