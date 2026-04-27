import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/memory_game_provider.dart';
import '../providers/sliding_puzzle_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final themeStyle = themeProvider.themeStyle;
    final headerGradient = AppDesign.appBarGradientForTheme(themeStyle);
    final theme = Theme.of(context);

    final currentPath = GoRouterState.of(context).uri.path;

    return Drawer(
      semanticLabel: TranslationService.translate(context, 'navigation'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          MergeSemantics(
            child: DrawerHeader(
              decoration: BoxDecoration(gradient: headerGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'BiblioGenius',
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
          ),
          _buildDrawerItem(
            context,
            icon: Icons.book,
            titleKey: 'nav_my_library',
            route: '/books',
            currentPath: currentPath,
            theme: theme,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.people,
            titleKey: 'nav_network',
            route: '/network',
            currentPath: currentPath,
            theme: theme,
          ),
          // Hide the "Loans" entry when both lending and borrowing modules are
          // disabled — there is nothing to manage on that screen anymore.
          if (themeProvider.canBorrowBooks || themeProvider.canLendBooks)
            _buildDrawerItem(
              context,
              icon: Icons.swap_horiz,
              titleKey: 'nav_loans',
              route: '/requests',
              currentPath: currentPath,
              theme: theme,
            ),
          const Divider(),
          _buildDrawerItem(
            context,
            icon: Icons.person,
            titleKey: 'nav_profile',
            route: '/profile',
            currentPath: currentPath,
            theme: theme,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.dashboard,
            titleKey: 'nav_dashboard',
            route: '/dashboard',
            currentPath: currentPath,
            theme: theme,
          ),
          if (themeProvider.gamesEnabled &&
              (themeProvider.memoryGameEnabled ||
                  themeProvider.slidingPuzzleEnabled))
            _buildGamesExpansionTile(
              context,
              themeProvider,
              currentPath,
              theme,
            ),
          _buildDrawerItem(
            context,
            icon: Icons.settings,
            titleKey: 'nav_settings',
            route: '/settings',
            currentPath: currentPath,
            theme: theme,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.help_outline,
            titleKey: 'nav_help',
            route: '/help',
            currentPath: currentPath,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildGamesExpansionTile(
    BuildContext context,
    ThemeProvider themeProvider,
    String currentPath,
    ThemeData theme,
  ) {
    final isGamesActive =
        currentPath.startsWith('/memory-game') ||
        currentPath.startsWith('/sliding-puzzle') ||
        currentPath.startsWith('/games');

    return ExpansionTile(
      leading: Icon(
        Icons.sports_esports,
        color: isGamesActive ? theme.colorScheme.primary : null,
      ),
      title: Text(
        TranslationService.translate(context, 'games_section'),
        style: isGamesActive
            ? TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      initiallyExpanded: isGamesActive,
      children: [
        if (themeProvider.memoryGameEnabled)
          _buildDrawerItem(
            context,
            icon: Icons.auto_stories,
            titleKey: 'memory_game_title',
            route: '/memory-game',
            currentPath: currentPath,
            theme: theme,
          ),
        if (themeProvider.slidingPuzzleEnabled)
          _buildDrawerItem(
            context,
            icon: Icons.grid_view,
            titleKey: 'sliding_puzzle_title',
            route: '/sliding-puzzle',
            currentPath: currentPath,
            theme: theme,
          ),
      ],
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String titleKey,
    required String route,
    required String currentPath,
    required ThemeData theme,
    bool isPush = false,
  }) {
    final isActive = currentPath.startsWith(route);

    return ListTile(
      leading: Icon(icon, color: isActive ? theme.colorScheme.primary : null),
      title: Text(
        TranslationService.translate(context, titleKey),
        style: isActive
            ? TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      selected: isActive,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
      ),
      onTap: () {
        Navigator.pop(context);
        // Same-route tap on Memory Game: force reset to setup
        if (route == '/memory-game' && currentPath.startsWith('/memory-game')) {
          final provider = context.read<MemoryGameProvider>();
          if (provider.phase != GamePhase.setup) {
            provider.resetToSetup();
            provider.loadDifficulties();
          }
          return;
        }
        // Same-route tap on Sliding Puzzle: force reset to setup
        if (route == '/sliding-puzzle' &&
            currentPath.startsWith('/sliding-puzzle')) {
          final provider = context.read<SlidingPuzzleProvider>();
          if (provider.phase != PuzzlePhase.setup) {
            provider.resetToSetup();
          }
          return;
        }
        if (isPush) {
          context.push(route);
        } else {
          context.go(route);
        }
      },
    );
  }
}
