import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbNotification;
import '../widgets/genie_app_bar.dart';

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
      context.read<NotificationProvider>().loadNotifications();
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
                  context, 'notifications_mark_all_read'),
              onPressed: () => provider.markAllRead(),
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
                    ? Center(
                        child: Text(
                          TranslationService.translate(
                              context, 'notifications_empty'),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: provider.notifications.length,
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

  void _handleTap(FrbNotification notif, NotificationProvider provider) {
    // Mark as read on tap
    if (notif.readAt == null) {
      provider.markRead(notif.id);
    }
    // Navigation to related screen can be added per event_type
  }
}

class _FilterBar extends StatelessWidget {
  final String? activeCategory;
  final ValueChanged<String?> onChanged;

  const _FilterBar({required this.activeCategory, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          _chip(context, null,
              TranslationService.translate(context, 'notifications_filter_all')),
          _chip(
              context,
              'connections',
              TranslationService.translate(
                  context, 'notifications_filter_connections')),
          _chip(
              context,
              'loans',
              TranslationService.translate(
                  context, 'notifications_filter_loans')),
          _chip(
              context,
              'discoveries',
              TranslationService.translate(
                  context, 'notifications_filter_discoveries')),
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

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'connections':
        return Icons.people;
      case 'loans':
        return Icons.swap_horiz;
      case 'discoveries':
        return Icons.auto_awesome;
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
            _iconForCategory(notification.category),
            color: catColor,
            size: 20,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: notification.body != null
            ? Text(
                notification.body!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _relativeTime(context, notification.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: TranslationService.translate(
                  context, 'notifications_dismiss'),
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
