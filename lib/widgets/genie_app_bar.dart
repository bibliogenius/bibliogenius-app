import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'bibliogenius_logo.dart';
import 'quick_actions_sheet.dart';

class GenieAppBar extends StatelessWidget implements PreferredSizeWidget {
  final dynamic title;
  final String? subtitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool showQuickActions; // Legacy direct buttons
  final List<Widget>? contextualQuickActions; // For the new Quick Actions menu
  final bool showBackButton;
  final VoidCallback? onBookAdded; // Callback when a book is added via quick actions
  final VoidCallback? onShelfCreated; // Callback when a shelf is created via quick actions

  const GenieAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.transparent = false,
    this.showQuickActions = false,
    this.contextualQuickActions,
    this.showBackButton = true,
    this.onBookAdded,
    this.onShelfCreated,
  });

  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    // Use provided subtitle, or fallback to library name from provider
    final displaySubtitle = subtitle ?? themeProvider.libraryName;

    // Get avatar info from provider (customizable avatar system)
    final avatarConfig = themeProvider.avatarConfig;

    // Theme-aware gradient - dark wood for Sorbonne, blue-purple for others
    // Theme-aware gradient
    final isSorbonne = themeProvider.themeStyle == 'sorbonne';
    final isDefault = themeProvider.themeStyle == 'default';

    final gradientColors = isSorbonne
        ? [const Color(0xFF1A0F0A), const Color(0xFF2D1810)] // Dark wood
        : isDefault
        ? [
            const Color(0xFF6BB0A9),
            const Color(0xFF5C8C9F),
          ] // Teal Gradient (6bb0a9 -> 5c8c9f)
        : [
            const Color(0xFF667eea),
            const Color(0xFF764ba2),
          ]; // Blue-purple (fallback)

    if (transparent) {
      // Use a transparent gradient/color if requested
      // We can just empty the list or use transparent colors
    }

    final canPop = GoRouter.of(context).canPop();
    final currentRoute = GoRouterState.of(context).uri.toString();
    final bool shouldShowBackButton =
        showBackButton && canPop && currentRoute != '/onboarding';

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading:
          leading ??
          (shouldShowBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => GoRouter.of(context).pop(),
                )
              : null),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: transparent
              ? null
              : LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: transparent ? Colors.transparent : null,
        ),
      ),
      elevation: 0,
      leadingWidth: 40, // Reduce space after hamburger menu
      title: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive breakpoints based on available title width
          final availableWidth = constraints.maxWidth;
          // More aggressive thresholds to hide rather than truncate
          final hideTitle = availableWidth < 120;
          final hideSubtitle = availableWidth < 180;
          final isCompact = availableWidth < 220;

          // Adaptive sizes
          final logoSize = isCompact ? 28.0 : 36.0;
          final titleFontSize = isCompact ? 15.0 : 20.0;
          final subtitleFontSize = isCompact ? 10.0 : 13.0;
          final spacing = isCompact ? 6.0 : 12.0;

          // Mobile check: If screen width is small, hide the spark icon explicitly
          // constraints.maxWidth refers to the Title widget constraint, not screen width.
          // Using MediaQuery from parent context is safer for overall device type check.
          final screenWidth = MediaQuery.of(context).size.width;
          final isMobile = screenWidth <= 600;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMobile)
                Container(
                  child: SizedBox(
                    width: logoSize,
                    height: logoSize,
                    child: BiblioGeniusLogo(
                      size: logoSize,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Hide text entirely if space is too tight (don't truncate)
              if (!hideTitle) ...[
                if (!isMobile) SizedBox(width: spacing),
                Flexible(
                  child: title is Widget
                      ? title
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: titleFontSize,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                            // Hide subtitle on narrower screens
                            if (!hideSubtitle && displaySubtitle.isNotEmpty)
                              Text(
                                displaySubtitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: subtitleFontSize,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                              ),
                          ],
                        ),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        // Global Quick Actions Button (New)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                // Determine if we are on the main library screen to hide redundant actions
                final currentPath = GoRouterState.of(context).uri.path;
                final hideGenericActions =
                    currentPath == '/books' ||
                    currentPath.startsWith('/books?');

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (sheetContext) => QuickActionsSheet(
                    contextualActions: contextualQuickActions,
                    hideGenericActions: hideGenericActions,
                    onBookAdded: onBookAdded,
                    onShelfCreated: onShelfCreated,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, color: Colors.white, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      MediaQuery.of(context).size.width > 600
                          ? TranslationService.translate(
                              context,
                              'quick_actions_title',
                            )
                          : 'Actions',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Quick Action Buttons (Scanner & Online Search) - only when explicitly enabled
        if (showQuickActions) ...[
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            tooltip: 'Scanner ISBN',
            onPressed: () async {
              final isbn = await context.push<String>('/scan');
              if (isbn != null && context.mounted) {
                final result = await context.push(
                  '/books/add',
                  extra: {'isbn': isbn},
                );
                if (result != null && context.mounted) {
                  if (onBookAdded != null) onBookAdded!();
                  if (result is int) {
                    context.push('/books/$result');
                  }
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.travel_explore,
              color: Colors.white,
            ), // Globe + search icon
            tooltip: 'Recherche en ligne',
            onPressed: () async {
              final result = await context.push('/search/external');
              if (result == true && onBookAdded != null) {
                onBookAdded!();
              }
            },
          ),
        ],
        if (actions != null) ...actions!,
        // Avatar
        if (avatarConfig?.style != 'initials')
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: GestureDetector(
              onTap: () => context.push('/profile'),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarConfig?.style == 'genie'
                      ? Color(
                          int.parse(
                            'FF${avatarConfig?.genieBackground ?? "fbbf24"}',
                            radix: 16,
                          ),
                        )
                      : Colors.white,
                ),
                child: ClipOval(
                  child: (avatarConfig?.isGenie ?? false)
                      ? Image.asset(
                          avatarConfig?.assetPath ?? 'assets/genie_mascot.jpg',
                          fit: BoxFit.cover,
                        )
                      : CachedNetworkImage(
                          imageUrl:
                              avatarConfig?.toUrl(size: 32, format: 'png') ??
                              '',
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.person, color: Colors.grey),
                        ),
                ),
              ),
            ),
          ),
      ],
      bottom: bottom,
      centerTitle: false,
      backgroundColor: Colors.transparent, // Required for flexibleSpace to show
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}
