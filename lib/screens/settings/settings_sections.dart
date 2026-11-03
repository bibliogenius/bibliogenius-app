import 'package:flutter/material.dart';

import 'account_section.dart';
import 'advanced_section.dart';
import 'backup_section.dart';
import 'catalogue_section.dart';
import 'contact_details_section.dart';
import 'find_books_section.dart';
import 'languages_section.dart';
import 'loans_section.dart';
import 'modules_section.dart';
import 'network_section.dart';
import 'notifications_section.dart';
import 'theme_section.dart';

/// One settings section: its page at `/settings/<name>`, its entry in the
/// section list and the widget that builds its body.
class SettingsSectionInfo {
  const SettingsSectionInfo({
    required this.name,
    required this.icon,
    required this.titleKey,
    required this.builder,
  });

  /// Route segment of the section's page.
  final String name;
  final IconData icon;
  final String titleKey;
  final Widget Function({Key? key}) builder;
}

/// A titled group of sections in the section list.
class SettingsSectionGroup {
  const SettingsSectionGroup(this.titleKey, this.sections);

  final String titleKey;
  final List<SettingsSectionInfo> sections;
}

/// Every section, in the order the list and the search results show them.
const settingsSectionGroups = [
  SettingsSectionGroup('settings_group_library', [
    SettingsSectionInfo(
      name: 'catalogue',
      icon: Icons.inventory_2_outlined,
      titleKey: 'content',
      builder: CatalogueSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'loans',
      icon: Icons.handshake_outlined,
      titleKey: 'modules_group_lending',
      builder: LoansSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'find-books',
      icon: Icons.saved_search,
      titleKey: 'settings_find_books_title',
      builder: FindBooksSettingsSection.new,
    ),
  ]),
  SettingsSectionGroup('settings_group_sharing', [
    SettingsSectionInfo(
      name: 'network',
      icon: Icons.wifi,
      titleKey: 'settings_network_title',
      builder: NetworkSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'contact-details',
      icon: Icons.contact_mail_outlined,
      titleKey: 'my_contact_details_title',
      builder: ContactDetailsSettingsSection.new,
    ),
  ]),
  SettingsSectionGroup('settings_group_app', [
    SettingsSectionInfo(
      name: 'display',
      icon: Icons.palette_outlined,
      titleKey: 'theme_title',
      builder: ThemeSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'languages',
      icon: Icons.translate,
      titleKey: 'languages_section',
      builder: LanguagesSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'features',
      icon: Icons.extension_outlined,
      titleKey: 'modules',
      builder: ModulesSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'notifications',
      icon: Icons.notifications_outlined,
      titleKey: 'settings_notifications',
      builder: NotificationsSettingsSection.new,
    ),
  ]),
  SettingsSectionGroup('settings_group_account', [
    SettingsSectionInfo(
      name: 'account',
      icon: Icons.devices,
      titleKey: 'settings_account_devices_title',
      builder: AccountSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'backup',
      icon: Icons.backup_outlined,
      titleKey: 'backup_section_title',
      builder: BackupSettingsSection.new,
    ),
    SettingsSectionInfo(
      name: 'advanced',
      icon: Icons.tune,
      titleKey: 'modules_group_advanced',
      builder: AdvancedSettingsSection.new,
    ),
  ]),
];

/// The section whose page is `/settings/<name>`, or null.
SettingsSectionInfo? settingsSectionNamed(String name) {
  for (final group in settingsSectionGroups) {
    for (final section in group.sections) {
      if (section.name == name) return section;
    }
  }
  return null;
}
