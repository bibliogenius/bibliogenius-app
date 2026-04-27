import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbNotification;
import '../utils/app_constants.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'bibliogenius_logo.dart';
import 'quick_actions_sheet.dart';
import '../theme/app_design.dart';

/// Whether the current app version is a beta release.
/// Reads from [AppConstants.isBeta].
bool isBetaVersion = AppConstants.isBeta;

void _showRenameLibraryDialog(
  BuildContext context,
  ThemeProvider themeProvider,
) {
  final controller = TextEditingController(text: themeProvider.libraryName);
  final api = Provider.of<ApiService>(context, listen: false);
  HubDirectoryProvider? hubProvider;
  try {
    hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
  } catch (_) {}

  Future<void> save(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    await themeProvider.setLibraryName(
      name,
      apiService: api,
      userInitiated: true,
    );
    final hubConfig = hubProvider?.config;
    if (hubConfig != null) {
      try {
        final bookCount = await FfiService().countBooks();
        await hubProvider!.register(
          nodeId: hubConfig.nodeId,
          displayName: name,
          bookCount: bookCount,
          isListed: hubConfig.isListed,
          requiresApproval: hubConfig.requiresApproval,
          acceptFrom: hubConfig.acceptFrom,
          allowBorrowing: hubConfig.allowBorrowing,
          locationCountry: themeProvider.country,
        );
      } catch (e) {
        debugPrint('Hub name update failed: $e');
      }
    }
  }

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          TranslationService.translate(context, 'rename_library_title'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: TranslationService.translate(
              context,
              'rename_library_hint',
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              save(value);
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                save(controller.text);
                Navigator.pop(dialogContext);
              }
            },
            child: Text(TranslationService.translate(context, 'save')),
          ),
        ],
      );
    },
  );
}

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
  final VoidCallback?
  onBookAdded; // Callback when a book is added via quick actions
  final VoidCallback?
  onShelfCreated; // Callback when a shelf is created via quick actions
  final String? preSelectedShelfId;
  final String? preSelectedCollectionId;
  final String? preSelectedCollectionName;
  final String? destinationName;
  final Widget? thirdSlotOverride;

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
    this.preSelectedShelfId,
    this.preSelectedCollectionId,
    this.preSelectedCollectionName,
    this.destinationName,
    this.thirdSlotOverride,
  });

  final bool transparent;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: _buildLeading(context),
      flexibleSpace: _buildFlexibleSpace(context),
      elevation: 0,
      leadingWidth: 40,
      title: _buildTitleWidget(context),
      actions: _buildActionsWidgets(context),
      bottom: bottom,
      centerTitle: false,
      backgroundColor: Colors.transparent,
    );
  }

  Widget? _buildLeading(BuildContext context) {
    if (leading != null) return leading;
    final canPop = GoRouter.of(context).canPop();
    final currentRoute = GoRouterState.of(context).uri.toString();
    final shouldShowBackButton =
        showBackButton && canPop && currentRoute != '/onboarding';
    if (!shouldShowBackButton) return null;
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      tooltip: TranslationService.translate(context, 'back'),
      onPressed: () => GoRouter.of(context).pop(),
    );
  }

  Widget _buildFlexibleSpace(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = AppDesign.appBarGradientForTheme(
      themeProvider.themeStyle,
    ).colors;
    return ExcludeSemantics(
      child: Container(
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
    );
  }

  Widget _buildTitleWidget(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final displaySubtitle = subtitle ?? themeProvider.libraryName;
    return LayoutBuilder(
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

        return MergeSemantics(
          child: ClipRect(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: TranslationService.translate(context, 'go_to_library'),
                  child: GestureDetector(
                    onTap: () => context.go('/books'),
                    child: SizedBox(
                      width: logoSize,
                      height: logoSize,
                      child: BiblioGeniusLogo(
                        size: logoSize,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Hide text entirely if space is too tight (don't truncate)
                if (!hideTitle) ...[
                  ExcludeSemantics(child: SizedBox(width: spacing)),
                  Flexible(
                    child: title is Widget
                        ? title
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (title != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        title.toString(),
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
                                    ),
                                  ],
                                ),
                              // Subtitle (library name) - tappable to edit when it's the default libraryName
                              // When title is null, subtitle is the primary text: use hideTitle threshold
                              if ((title != null
                                      ? !hideSubtitle
                                      : !hideTitle) &&
                                  displaySubtitle.isNotEmpty)
                                GestureDetector(
                                  onTap: subtitle == null
                                      ? () => _showRenameLibraryDialog(
                                          context,
                                          themeProvider,
                                        )
                                      : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displaySubtitle,
                                          style: TextStyle(
                                            fontWeight: title != null
                                                ? FontWeight.w400
                                                : FontWeight.w600,
                                            fontSize: title != null
                                                ? subtitleFontSize
                                                : titleFontSize,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.fade,
                                          softWrap: false,
                                        ),
                                      ),
                                      if (subtitle == null) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.edit,
                                          size: subtitleFontSize - 1,
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActionsWidgets(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final avatarConfig = themeProvider.avatarConfig;
    return [
      // Notification bell with unread badge (hidden when notifications disabled)
      if (context.watch<ThemeProvider>().notificationsEnabled)
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Consumer<NotificationProvider>(
            builder: (context, notifProvider, child) {
              final count = notifProvider.unreadCount;
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(fontSize: 10),
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                ),
                tooltip: TranslationService.translate(
                  context,
                  'notifications_title',
                ),
                onPressed: () =>
                    _showNotificationPopover(context, notifProvider),
              );
            },
          ),
        ),
      // Global Quick Actions Button (New)
      Semantics(
        button: true,
        label: TranslationService.translate(context, 'quick_actions_title'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
              onTap: () {
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
                    onBookAdded: onBookAdded,
                    onShelfCreated: onShelfCreated,
                    preSelectedShelfId: preSelectedShelfId,
                    preSelectedCollectionId: preSelectedCollectionId,
                    preSelectedCollectionName: preSelectedCollectionName,
                    destinationName: destinationName,
                    thirdSlotOverride: thirdSlotOverride,
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
                          : TranslationService.translate(
                              context,
                              'quick_actions_short',
                            ),
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
      ),

      // Quick Action Buttons (Scanner & Online Search) - only when explicitly enabled
      if (showQuickActions) ...[
        IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
          tooltip: TranslationService.translate(context, 'scan_isbn'),
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
          tooltip: TranslationService.translate(context, 'search_online'),
          onPressed: () async {
            final result = await context.push('/search/external');
            if (result == true && onBookAdded != null) {
              onBookAdded!();
            }
          },
        ),
      ],
      if (actions != null) ...actions!,
      IconButton(
        icon: const Icon(Icons.settings_outlined, color: Colors.white),
        tooltip: TranslationService.translate(context, 'tooltip_open_settings'),
        onPressed: () => context.go('/settings'),
      ),
      // Avatar
      if (avatarConfig?.style != 'initials')
        Semantics(
          button: true,
          label: TranslationService.translate(context, 'nav_profile'),
          child: Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: GestureDetector(
              onTap: () => context.push('/profile'),
              child: Container(
                width: 34,
                height: 34,
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
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 2,
                  ),
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
        ),
    ];
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}

/// Sliver variant of [GenieAppBar] for use in `CustomScrollView` /
/// `NestedScrollView`. Renders the same visual content as [GenieAppBar] but
/// supports collapse-on-scroll behaviors (`floating`, `snap`, `pinned`).
///
/// This shares the private builder methods with [GenieAppBar] to keep a
/// single source of truth for the header's content.
class GenieSliverAppBar extends StatelessWidget {
  final GenieAppBar source;
  final bool floating;
  final bool snap;
  final bool pinned;
  final bool forceElevated;

  const GenieSliverAppBar({
    super.key,
    required this.source,
    this.floating = true,
    this.snap = true,
    this.pinned = false,
    this.forceElevated = false,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      automaticallyImplyLeading: source.automaticallyImplyLeading,
      leading: source._buildLeading(context),
      flexibleSpace: source._buildFlexibleSpace(context),
      elevation: 0,
      leadingWidth: 40,
      title: source._buildTitleWidget(context),
      actions: source._buildActionsWidgets(context),
      bottom: source.bottom,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      floating: floating,
      snap: snap,
      pinned: pinned,
      forceElevated: forceElevated,
    );
  }
}

void _showNotificationPopover(
  BuildContext context,
  NotificationProvider provider,
) {
  provider.loadNotifications();
  showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) {
      return _NotificationPopover(provider: provider);
    },
  );
}

class _NotificationPopover extends StatelessWidget {
  final NotificationProvider provider;

  const _NotificationPopover({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tp = context.read<ThemeProvider>();
    final gradient = AppDesign.appBarGradientForTheme(tp.themeStyle);
    final gradientColors = gradient.colors;
    final accentColor = gradientColors.first;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: kToolbarHeight + 8, right: 8),
        child: Material(
          elevation: 12,
          shadowColor: accentColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
            child: ListenableBuilder(
              listenable: provider,
              builder: (context, _) {
                final notifs = provider.notifications.take(5).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with app gradient
                    Container(
                      decoration: BoxDecoration(gradient: gradient),
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            TranslationService.translate(
                              context,
                              'notifications_title',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          if (provider.unreadCount > 0)
                            GestureDetector(
                              onTap: () => provider.markAllRead(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  TranslationService.translate(
                                    context,
                                    'notifications_mark_all_read',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Notifications list
                    if (provider.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (notifs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 32,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              TranslationService.translate(
                                context,
                                'notifications_empty',
                              ),
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    else
                      ...notifs.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final n = entry.value;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PopoverNotifTile(
                              notification: n,
                              accentColor: accentColor,
                              onTap: () {
                                if (n.readAt == null) {
                                  provider.markRead(n.id);
                                }
                                Navigator.of(context).pop();
                                _navigateForNotification(context, n);
                              },
                            ),
                            if (idx < notifs.length - 1)
                              Divider(
                                height: 1,
                                indent: 46,
                                color: cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                          ],
                        );
                      }),
                    // "See all" footer
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/notifications');
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'notifications_see_all',
                            ),
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoverNotifTile extends StatelessWidget {
  final FrbNotification notification;
  final Color accentColor;
  final VoidCallback onTap;

  const _PopoverNotifTile({
    required this.notification,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUnread = notification.readAt == null;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread ? accentColor.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForEvent(notification.eventType),
                size: 16,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _formatTitle(context, notification),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  color: cs.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _relativeTime(notification.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForEvent(String eventType) {
  switch (eventType) {
    case 'connection_request':
      return Icons.person_add;
    case 'connection_accepted':
      return Icons.how_to_reg;
    case 'borrow_request':
      return Icons.menu_book;
    case 'borrow_accepted':
      return Icons.check_circle_outline;
    case 'book_returned':
      return Icons.assignment_return;
    case 'book_reclaimed':
      return Icons.replay;
    case 'borrow_rejected':
      return Icons.cancel_outlined;
    case 'wishlist_match':
      return Icons.favorite;
    case 'welcome':
      return Icons.waving_hand;
    default:
      return Icons.notifications;
  }
}

String _formatTitle(BuildContext context, FrbNotification n) {
  final t = n.title;
  final b = n.body;
  switch (n.eventType) {
    case 'connection_request':
      return TranslationService.translate(
        context,
        'notif_connection_request',
      ).replaceAll('{name}', t);
    case 'connection_accepted':
      return TranslationService.translate(
        context,
        'notif_connection_accepted',
      ).replaceAll('{name}', t);
    case 'borrow_request':
      return TranslationService.translate(
        context,
        'notif_borrow_request',
      ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
    case 'borrow_accepted':
      return TranslationService.translate(
        context,
        'notif_borrow_accepted',
      ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
    case 'book_returned':
      return TranslationService.translate(
        context,
        'notif_book_returned',
      ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
    case 'book_reclaimed':
      return TranslationService.translate(
        context,
        'notif_book_reclaimed',
      ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
    case 'borrow_rejected':
      return TranslationService.translate(
        context,
        'notif_borrow_rejected',
      ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
    case 'wishlist_match':
      return TranslationService.translate(
        context,
        'notif_wishlist_match',
      ).replaceAll('{book}', t).replaceAll('{source}', b ?? '');
    case 'welcome':
      return TranslationService.translate(context, 'notif_welcome');
    default:
      return t;
  }
}

String _relativeTime(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${date.day}/${date.month}';
}

void _navigateForNotification(BuildContext context, FrbNotification notif) {
  switch (notif.eventType) {
    case 'connection_request':
    case 'connection_accepted':
    case 'new_follower':
    case 'follow_request':
      context.push('/network');
      break;
    case 'borrow_request':
      context.push('/requests?tab=requests');
      break;
    case 'borrow_accepted':
      context.push('/requests?tab=borrowed');
      break;
    case 'book_returned':
      context.push('/requests?tab=lent&status=returned');
      break;
    case 'book_reclaimed':
      context.push('/requests?tab=borrowed');
      break;
    case 'borrow_rejected':
      context.push('/requests?tab=requests');
      break;
    case 'wishlist_match':
      // Open full notifications screen for rich navigation (peer library + search)
      context.push('/notifications');
      break;
    default:
      context.push('/notifications');
  }
}
