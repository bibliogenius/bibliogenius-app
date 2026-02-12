import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';
import 'app_drawer.dart';
import '../utils/global_keys.dart';

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width > 600;

    // Build navigation items (always includes loans menu)
    final navItems = _buildNavItems(context);

    return Scaffold(
      key: GlobalKeys.rootScaffoldKey,
      drawer: useRail ? null : const AppDrawer(),
      body: Row(
        children: [
          if (useRail)
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        minWidth: 88, // Slightly wider for larger font
                        selectedIndex: _calculateSelectedIndex(
                          context,
                          navItems,
                        ),
                        onDestinationSelected: (int index) =>
                            _onItemTapped(index, context, navItems),
                        labelType: NavigationRailLabelType.all,
                        selectedLabelTextStyle: TextStyle(
                          fontSize: 14, // 2px larger than default 12
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        unselectedLabelTextStyle: TextStyle(
                          fontSize: 14, // 2px larger than default 12
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        destinations: navItems
                            .map((item) => item.destination)
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (useRail) const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  List<_NavItem> _buildNavItems(BuildContext context) {
    return [
      _NavItem(
        route: '/books',
        matchPrefixes: ['/books', '/shelves', '/collections'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.book),
          label: Text(TranslationService.translate(context, 'library')),
        ),
      ),
      _NavItem(
        route: '/network',
        matchPrefixes: ['/network', '/contacts', '/peers', '/requests'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.people),
          label: Text(TranslationService.translate(context, 'network')),
        ),
      ),
      _NavItem(
        route: '/profile',
        destination: NavigationRailDestination(
          icon: const Icon(Icons.person),
          label: Text(TranslationService.translate(context, 'profile')),
        ),
      ),
      _NavItem(
        route: '/dashboard',
        matchPrefixes: ['/dashboard', '/statistics'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.dashboard),
          label: Text(TranslationService.translate(context, 'dashboard')),
        ),
      ),

      _NavItem(
        route: '/settings',
        destination: NavigationRailDestination(
          icon: const Icon(Icons.settings),
          label: Text(TranslationService.translate(context, 'nav_settings')),
        ),
      ),
      _NavItem(
        route: '/help',
        destination: NavigationRailDestination(
          icon: const Icon(Icons.help_outline),
          label: Text(TranslationService.translate(context, 'nav_help')),
        ),
      ),
      // TODO: Move to Settings after testing phase
      _NavItem(
        route: '/feedback',
        isPush: true,
        destination: NavigationRailDestination(
          icon: const Icon(Icons.bug_report),
          label: Text(TranslationService.translate(context, 'nav_report_bug')),
        ),
      ),
    ];
  }

  static int _calculateSelectedIndex(
    BuildContext context,
    List<_NavItem> navItems,
  ) {
    final String location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < navItems.length; i++) {
      final item = navItems[i];
      if (item.matchPrefixes != null) {
        for (final prefix in item.matchPrefixes!) {
          if (location.startsWith(prefix)) return i;
        }
      } else if (location.startsWith(item.route)) {
        return i;
      }
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context, List<_NavItem> navItems) {
    if (index >= 0 && index < navItems.length) {
      final item = navItems[index];
      if (item.isPush) {
        context.push(item.route);
      } else {
        context.go(item.route);
      }
    }
  }
}

class _NavItem {
  final String route;
  final List<String>? matchPrefixes;
  final NavigationRailDestination destination;
  final bool isPush;

  _NavItem({
    required this.route,
    required this.destination,
    this.matchPrefixes,
    this.isPush = false,
  });
}
