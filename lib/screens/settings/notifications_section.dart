import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Notifications section: the main switch, then what it lets through.
class NotificationsSettingsSection extends StatelessWidget {
  const NotificationsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'settings_notifications',
      'settings_notif_enabled',
      'settings_notif_enabled_desc',
      'settings_notif_connections',
      'settings_notif_connections_desc',
      'settings_notif_loans',
      'settings_notif_loans_desc',
      'settings_notif_discoveries',
      'settings_notif_discoveries_desc',
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      name: 'notifications',
      children: [
        SettingsToggleCard(
          titleKey: 'settings_notif_enabled',
          descKey: 'settings_notif_enabled_desc',
          icon: Icons.notifications_outlined,
          value: themeProvider.notificationsEnabled,
          onChanged: (value) => themeProvider.setNotificationsEnabled(value),
          helpTopicId: 'notif_enabled',
        ),
        if (themeProvider.notificationsEnabled) ...[
          SettingsToggleCard(
            titleKey: 'settings_notif_connections',
            descKey: 'settings_notif_connections_desc',
            icon: Icons.people_outline,
            value: themeProvider.notifConnectionsEnabled,
            onChanged: (value) =>
                themeProvider.setNotifConnectionsEnabled(value),
            helpTopicId: 'notif_connections',
            indent: 16,
          ),
          SettingsToggleCard(
            titleKey: 'settings_notif_loans',
            descKey: 'settings_notif_loans_desc',
            icon: Icons.menu_book_outlined,
            value: themeProvider.notifLoansEnabled,
            onChanged: (value) => themeProvider.setNotifLoansEnabled(value),
            helpTopicId: 'notif_loans',
            indent: 16,
          ),
          SettingsToggleCard(
            titleKey: 'settings_notif_discoveries',
            descKey: 'settings_notif_discoveries_desc',
            icon: Icons.explore_outlined,
            value: themeProvider.notifDiscoveriesEnabled,
            onChanged: (value) =>
                themeProvider.setNotifDiscoveriesEnabled(value),
            helpTopicId: 'notif_discoveries',
            indent: 16,
          ),
        ],
      ],
    );
  }
}
