import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbNotification;
import '../widgets/genie_app_bar.dart';
import '../widgets/premium_empty_state.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotificationProvider>();
      provider.loadNotifications().then((_) {
        if (provider.unreadCount > 0) {
          provider.markAllRead();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'notifications_title'),
        actions: [
          if (provider.unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: TranslationService.translate(
                context,
                'notifications_mark_all_read',
              ),
              onPressed: () => provider.markAllRead(),
            ),
          if (provider.notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: TranslationService.translate(
                context,
                'notifications_clear_all',
              ),
              onPressed: () => _confirmClearAll(provider),
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          _FilterBar(
            activeCategory: provider.activeCategory,
            onChanged: (cat) => provider.filterByCategory(cat),
          ),
          // List
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.notifications.isEmpty
                ? PremiumEmptyState(
                    icon: Icons.notifications_none_rounded,
                    message: TranslationService.translate(
                      context,
                      'notifications_empty',
                    ),
                    description: TranslationService.translate(
                      context,
                      'notifications_empty_desc',
                    ),
                    colorOverride: cs.primary,
                  )
                : ListView.separated(
                    itemCount: provider.notifications.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 72,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                    itemBuilder: (context, index) {
                      final notif = provider.notifications[index];
                      return _NotificationTile(
                        notification: notif,
                        onDismiss: () => provider.dismiss(notif.id),
                        onTap: () => _handleTap(notif, provider),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(NotificationProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(
            context,
            'notifications_clear_all_confirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              provider.clearAll();
            },
            child: Text(
              TranslationService.translate(context, 'notifications_clear_all'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(FrbNotification notif, NotificationProvider provider) {
    // Mark as read on tap
    if (notif.readAt == null) {
      provider.markRead(notif.id);
    }
    // Navigate to relevant screen based on event type
    _navigateForNotification(notif);
  }

  Future<void> _navigateForNotification(FrbNotification notif) async {
    switch (notif.eventType) {
      case 'connection_request':
      case 'connection_accepted':
      case 'new_follower':
      case 'follow_request':
        // Go to network / contacts
        context.push('/network');
        break;
      case 'borrow_request':
        // Go to received requests tab
        context.push('/requests?tab=requests');
        break;
      case 'borrow_accepted':
      case 'loan_offered':
        // Go to borrowing tab
        context.push('/requests?tab=borrowed');
        break;
      case 'borrow_rejected':
        // Go to outgoing requests tab
        context.push('/requests?tab=requests');
        break;
      case 'book_returned':
        // Go to lent tab with returned filter
        context.push('/requests?tab=lent&status=returned');
        break;
      case 'book_reclaimed':
        // Go to borrowed tab (borrower's perspective)
        context.push('/requests?tab=borrowed');
        break;
      case 'wishlist_match':
        // Navigate to the peer's library, filtered by the book title
        await _navigateToWishlistMatch(notif);
        break;
      default:
        break;
    }
  }

  /// Navigate to the peer's library filtered by the matched book.
  /// ref_id format: "{peer_id}:{isbn}", ref_type: "peer" or "directory"
  Future<void> _navigateToWishlistMatch(FrbNotification notif) async {
    if (notif.refId == null || !notif.refId!.contains(':')) {
      // Fallback: go to wishlist
      if (mounted) context.push('/books?status=wanting');
      return;
    }

    final parts = notif.refId!.split(':');
    final sourceId = parts[0];
    final bookTitle =
        notif.title; // The book title is stored in notification.title

    if (notif.refType == 'peer') {
      final peerId = int.tryParse(sourceId);
      if (peerId == null) {
        if (mounted) context.push('/books?status=wanting');
        return;
      }

      // Look up peer info
      try {
        final api = context.read<ApiService>();
        final response = await api.getPeers();
        final peers = (response.data as Map?)?['data'] as List?;
        if (peers != null) {
          for (final p in peers) {
            if (p is Map && p['id'] == peerId) {
              if (mounted) {
                final hasRelay =
                    p['relay_url'] != null && p['mailbox_id'] != null;
                context.push(
                  '/peers/$peerId/books',
                  extra: {
                    'id': peerId,
                    'name': p['name'] ?? '',
                    'url': p['url'] ?? '',
                    'hasRelayCredentials': hasRelay,
                    'nodeId': p['library_uuid'] as String?,
                    'initialSearch': bookTitle,
                  },
                );
              }
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Wishlist match navigation error: $e');
      }
    }

    // Fallback
    if (mounted) context.push('/books?status=wanting');
  }
}

class _FilterBar extends StatelessWidget {
  final String? activeCategory;
  final ValueChanged<String?> onChanged;

  const _FilterBar({required this.activeCategory, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _chip(
            context,
            null,
            TranslationService.translate(context, 'notifications_filter_all'),
          ),
          const SizedBox(width: 8),
          if (tp.notifConnectionsEnabled) ...[
            _chip(
              context,
              'connections',
              TranslationService.translate(
                context,
                'notifications_filter_connections',
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (tp.notifLoansEnabled) ...[
            _chip(
              context,
              'loans',
              TranslationService.translate(
                context,
                'notifications_filter_loans',
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (tp.notifDiscoveriesEnabled)
            _chip(
              context,
              'discoveries',
              TranslationService.translate(
                context,
                'notifications_filter_discoveries',
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String? category, String label) {
    final selected = activeCategory == category;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(category),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final FrbNotification notification;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onDismiss,
    required this.onTap,
  });

  IconData _iconForEvent(String eventType) {
    switch (eventType) {
      case 'connection_request':
        return Icons.person_add;
      case 'connection_accepted':
        return Icons.how_to_reg;
      case 'new_follower':
        return Icons.person_add;
      case 'follow_request':
        return Icons.person_add_alt;
      case 'borrow_request':
        return Icons.menu_book;
      case 'borrow_accepted':
        return Icons.check_circle_outline;
      case 'loan_offered':
        return Icons.auto_stories;
      case 'borrow_rejected':
        return Icons.cancel_outlined;
      case 'book_returned':
        return Icons.assignment_return;
      case 'book_reclaimed':
        return Icons.replay;
      case 'wishlist_match':
        return Icons.favorite;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForCategory(String category, ColorScheme cs) {
    switch (category) {
      case 'connections':
        return cs.primary;
      case 'loans':
        return cs.tertiary;
      case 'discoveries':
        return cs.secondary;
      default:
        return cs.outline;
    }
  }

  /// Build a human-readable title based on event type.
  String _displayTitle(BuildContext context) {
    final t = notification.title;
    final b = notification.body;
    switch (notification.eventType) {
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
      case 'new_follower':
        return TranslationService.translate(
          context,
          'notif_new_follower',
        ).replaceAll('{name}', t);
      case 'follow_request':
        return TranslationService.translate(
          context,
          'notif_follow_request',
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
      case 'loan_offered':
        return TranslationService.translate(
          context,
          'notif_loan_offered',
        ).replaceAll('{name}', b ?? '').replaceAll('{book}', t);
      case 'borrow_rejected':
        return TranslationService.translate(
          context,
          'notif_borrow_rejected',
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
      case 'wishlist_match':
        // Aggregated form for curated list imports (ref_type 'import'):
        // title = list name, body = matched book count.
        if (notification.refType == 'import') {
          return TranslationService.translate(
            context,
            'notif_wishlist_match_import',
          ).replaceAll('{list}', t).replaceAll('{count}', b ?? '');
        }
        return TranslationService.translate(
          context,
          'notif_wishlist_match',
        ).replaceAll('{book}', t).replaceAll('{source}', b ?? '');
      case 'loan_due_reminder':
      case 'loan_due_today':
        return b ?? t;
      case 'welcome':
        return TranslationService.translate(context, 'notif_welcome');
      default:
        return t;
    }
  }

  String _relativeTime(BuildContext context, String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) {
      return TranslationService.translate(context, 'time_just_now');
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}j';
    }
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUnread = notification.readAt == null;
    final catColor = _colorForCategory(notification.category, cs);

    final displayTitle = _displayTitle(context);

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: cs.errorContainer,
        child: Icon(Icons.delete, color: cs.onErrorContainer),
      ),
      child: ListTile(
        onTap: onTap,
        tileColor: isUnread ? catColor.withValues(alpha: 0.06) : null,
        leading: CircleAvatar(
          backgroundColor: catColor.withValues(alpha: 0.15),
          child: Icon(
            _iconForEvent(notification.eventType),
            color: catColor,
            size: 20,
          ),
        ),
        title: Text(
          displayTitle,
          style: TextStyle(
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _relativeTime(context, notification.createdAt),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: TranslationService.translate(
                context,
                'notifications_dismiss',
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: cs.outline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
