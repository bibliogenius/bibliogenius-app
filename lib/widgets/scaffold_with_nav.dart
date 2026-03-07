import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/pending_peers_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import 'app_drawer.dart';
import 'flash_message_bar.dart';
import '../utils/global_keys.dart';

/// Returns a hamburger menu button if the drawer is available, null otherwise.
/// Used by screens that show the drawer toggle on mobile.
Widget? buildDrawerLeading(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width > 600) return null;
  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  if (themeProvider.bottomNavEnabled) return null;
  return IconButton(
    icon: const Icon(Icons.menu, color: Colors.white),
    tooltip: TranslationService.translate(context, 'tooltip_open_menu'),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width > 600;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool useBottomNav = !useRail && themeProvider.bottomNavEnabled;

    // Build navigation items (always includes loans menu)
    final navItems = _buildNavItems(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: GlobalKeys.rootScaffoldKey,
      drawer: useRail || useBottomNav ? null : const AppDrawer(),
      bottomNavigationBar: useBottomNav
          ? _buildBottomNav(context, themeProvider)
          : null,
      body: Semantics(
        explicitChildNodes: true,
        child: Row(
        children: [
          if (useRail)
            Semantics(
              label: TranslationService.translate(context, 'navigation'),
              child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        minWidth: 88,
                        backgroundColor: isDark
                            ? theme.colorScheme.surface
                            : null,
                        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                        selectedIndex: _calculateSelectedIndex(
                          context,
                          navItems,
                        ),
                        onDestinationSelected: (int index) =>
                            _onItemTapped(index, context, navItems),
                        labelType: NavigationRailLabelType.all,
                        selectedLabelTextStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                        unselectedLabelTextStyle: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        selectedIconTheme: IconThemeData(
                          color: theme.colorScheme.primary,
                        ),
                        unselectedIconTheme: IconThemeData(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
            ),
          if (useRail) ExcludeSemantics(child: VerticalDivider(
            thickness: 1,
            width: 1,
            color: theme.dividerColor,
          )),
          Expanded(
            child: Column(
              children: [
                FlashMessageBar(applyTopSafeArea: !useRail),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context, ThemeProvider themeProvider) {
    final bottomItems = _buildBottomNavItems();
    final selectedIndex = _calculateBottomNavIndex(context, bottomItems);

    final theme = Theme.of(context);

    return Semantics(
      label: TranslationService.translate(context, 'navigation'),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(
            TextStyle(
              fontSize: 11,
              overflow: TextOverflow.ellipsis,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index < bottomItems.length) {
            context.go(bottomItems[index].route);
          } else {
            _showMoreSheet(context, themeProvider);
          }
        },
        destinations: [
          ...bottomItems.map((item) => NavigationDestination(
            icon: item.hasBadge
                ? Consumer<PendingPeersProvider>(
                    builder: (context, provider, child) {
                      final count = provider.pendingCount;
                      return Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: Icon(item.icon),
                      );
                    },
                  )
                : Icon(item.icon),
            selectedIcon: item.hasBadge
                ? Consumer<PendingPeersProvider>(
                    builder: (context, provider, child) {
                      final count = provider.pendingCount;
                      return Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: Icon(item.selectedIcon),
                      );
                    },
                  )
                : Icon(item.selectedIcon),
            label: TranslationService.translate(context, item.labelKey),
            tooltip: TranslationService.translate(context, item.labelKey),
          )),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: TranslationService.translate(context, 'nav_more'),
            tooltip: TranslationService.translate(context, 'nav_more'),
          ),
        ],
      ),
      ),
    );
  }

  List<_BottomNavItem> _buildBottomNavItems() {
    return [
      _BottomNavItem(
        route: '/books',
        matchPrefixes: ['/books', '/shelves', '/collections'],
        icon: Icons.book_outlined,
        selectedIcon: Icons.book,
        labelKey: 'btm_library',
      ),
      _BottomNavItem(
        route: '/network',
        matchPrefixes: ['/network', '/contacts', '/peers'],
        icon: Icons.people_outlined,
        selectedIcon: Icons.people,
        labelKey: 'btm_network',
        hasBadge: true,
      ),
      _BottomNavItem(
        route: '/requests',
        matchPrefixes: ['/requests'],
        icon: Icons.swap_horiz,
        selectedIcon: Icons.swap_horiz,
        labelKey: 'btm_loans',
      ),
      _BottomNavItem(
        route: '/profile',
        matchPrefixes: ['/profile'],
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        labelKey: 'btm_profile',
      ),
      _BottomNavItem(
        route: '/dashboard',
        matchPrefixes: ['/dashboard', '/statistics'],
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        labelKey: 'btm_stats',
      ),
    ];
  }

  int _calculateBottomNavIndex(
    BuildContext context,
    List<_BottomNavItem> items,
  ) {
    final String location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < items.length; i++) {
      for (final prefix in items[i].matchPrefixes) {
        if (location.startsWith(prefix)) return i;
      }
    }
    // Routes that belong to "More"
    const morePrefixes = [
      '/games', '/memory-game', '/sliding-puzzle',
      '/settings', '/operation-log', '/device-pairing', '/sync-review',
      '/help',
    ];
    for (final prefix in morePrefixes) {
      if (location.startsWith(prefix)) return items.length; // "More" index
    }
    return 0;
  }

  void _showMoreSheet(BuildContext context, ThemeProvider themeProvider) {
    final theme = Theme.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final gamesVisible = themeProvider.gamesEnabled &&
        (themeProvider.memoryGameEnabled || themeProvider.slidingPuzzleEnabled);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (gamesVisible)
                ListTile(
                  leading: Icon(
                    Icons.sports_esports,
                    color: currentPath.startsWith('/games') ||
                            currentPath.startsWith('/memory-game') ||
                            currentPath.startsWith('/sliding-puzzle')
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(TranslationService.translate(
                      context, 'games_section')),
                  selected: currentPath.startsWith('/games') ||
                      currentPath.startsWith('/memory-game') ||
                      currentPath.startsWith('/sliding-puzzle'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.go('/games');
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.settings,
                  color: currentPath.startsWith('/settings')
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(TranslationService.translate(
                    context, 'nav_settings')),
                selected: currentPath.startsWith('/settings'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/settings');
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.help_outline,
                  color: currentPath.startsWith('/help')
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(TranslationService.translate(
                    context, 'nav_help')),
                selected: currentPath.startsWith('/help'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/help');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_NavItem> _buildNavItems(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
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
        matchPrefixes: ['/network', '/contacts', '/peers'],
        destination: NavigationRailDestination(
          icon: Consumer<PendingPeersProvider>(
            builder: (context, provider, child) {
              final count = provider.pendingCount;
              return Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.people),
              );
            },
          ),
          label: Text(TranslationService.translate(context, 'nav_network')),
        ),
      ),
      _NavItem(
        route: '/requests',
        matchPrefixes: ['/requests'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.swap_horiz),
          label: Text(TranslationService.translate(context, 'nav_loans')),
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
      if (themeProvider.gamesEnabled &&
          (themeProvider.memoryGameEnabled || themeProvider.slidingPuzzleEnabled))
        _NavItem(
          route: '/games',
          matchPrefixes: ['/games', '/memory-game', '/sliding-puzzle'],
          destination: NavigationRailDestination(
            icon: const Icon(Icons.sports_esports),
            label: Text(TranslationService.translate(context, 'games_section')),
          ),
        ),
      _NavItem(
        route: '/settings',
        matchPrefixes: ['/settings', '/operation-log', '/device-pairing', '/sync-review'],
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

class _BottomNavItem {
  final String route;
  final List<String> matchPrefixes;
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final bool hasBadge;

  _BottomNavItem({
    required this.route,
    required this.matchPrefixes,
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    this.hasBadge = false,
  });
}
