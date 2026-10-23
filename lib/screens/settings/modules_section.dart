import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../../widgets/contextual_help_sheet.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../providers/ownership_preference_provider.dart';
import '../../services/ffi_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/book_filters.dart';
import '../../utils/cover_camera_helper.dart';
import 'settings_scope.dart';

/// Modules accordion
class ModulesSettingsSection extends StatefulWidget {
  const ModulesSettingsSection({super.key});

  @override
  State<ModulesSettingsSection> createState() => _ModulesSettingsSectionState();
}

class _ModulesSettingsSectionState extends State<ModulesSettingsSection> {
  // Loan settings
  int _defaultLoanDurationDays = 21;
  bool _perBookDurationEnabled = false;
  int _reminderDaysBeforeDue = 2;
  bool _loanSettingsLoaded = false;
  // Resolved asynchronously: on Android it depends on Play services.
  bool _coverScannerAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadLoanSettings();
    CoverCameraHelper.isDocumentScannerAvailable().then((available) {
      if (mounted && available) {
        setState(() => _coverScannerAvailable = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'modules',
      'quotes_module',
      'quotes_module_desc',
      'gamification_module',
      'gamification_desc',
      'games_module',
      'games_module_desc',
      'memory_game_module',
      'memory_game_module_desc',
      'sliding_puzzle_module',
      'sliding_puzzle_module_desc',
      'network_gamification',
      'network_gamification_desc',
      'share_gamification_stats',
      'share_gamification_stats_desc',
      'collections_module',
      'collections_module_desc',
      'group_by_collections_title',
      'group_by_collections_desc',
      'settings_show_not_owned_books',
      'settings_show_not_owned_books_desc',
      'commerce_module',
      'commerce_module_desc',
      'audio_module',
      'audio_module_desc',
      'auto_approve_loans_title',
      'auto_approve_loans_desc',
      'enable_borrowing_module',
      'borrowing_module_desc',
      'settings_allow_private_books',
      'settings_allow_private_books_desc',
      'module_digital_formats',
      'module_digital_formats_desc',
      // Only where the toggle shows, with the description it shows.
      if (_coverScannerAvailable) ...[
        'module_cover_auto_crop',
        io.Platform.isAndroid
            ? 'module_cover_auto_crop_desc_android'
            : 'module_cover_auto_crop_desc',
      ],
      'mcp_integration',
      'mcp_description',
      'settings_linked_devices',
      'settings_linked_devices_desc',
      'settings_notif_enabled',
      'settings_notif_enabled_desc',
      'settings_notif_connections',
      'settings_notif_connections_desc',
      'settings_notif_loans',
      'settings_notif_loans_desc',
      'settings_notif_discoveries',
      'settings_notif_discoveries_desc',
      'module_operation_log_viewer',
      'module_operation_log_desc',
      'enable_taxonomy',
      'settings_notifications',
      'settings_developer_tools',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('modules_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.extension_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'modules'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          // === Group 1: Reading & Fun ===
          _buildModulesGroupHeader(context, 'modules_group_reading_fun'),
          _buildModuleToggle(
            context,
            'quotes_module',
            'quotes_module_desc',
            Icons.format_quote,
            themeProvider.quotesEnabled,
            (value) => themeProvider.setQuotesEnabled(value),
            helpTopicId: 'quotes_module',
          ),
          _buildModuleToggle(
            context,
            'gamification_module',
            'gamification_desc',
            Icons.emoji_events,
            themeProvider.gamificationEnabled,
            (value) => themeProvider.setGamificationEnabled(value),
            helpTopicId: 'gamification_module',
          ),
          _buildModuleToggle(
            context,
            'games_module',
            'games_module_desc',
            Icons.sports_esports,
            themeProvider.gamesEnabled,
            (value) => themeProvider.setGamesEnabled(value),
            helpTopicId: 'games_module',
          ),
          if (themeProvider.gamesEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildModuleToggle(
                context,
                'memory_game_module',
                'memory_game_module_desc',
                Icons.auto_stories,
                themeProvider.memoryGameEnabled,
                (value) => themeProvider.setMemoryGameEnabled(value),
                helpTopicId: 'memory_game',
              ),
            ),
          if (themeProvider.gamesEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildModuleToggle(
                context,
                'sliding_puzzle_module',
                'sliding_puzzle_module_desc',
                Icons.grid_view,
                themeProvider.slidingPuzzleEnabled,
                (value) => themeProvider.setSlidingPuzzleEnabled(value),
                helpTopicId: 'sliding_puzzle',
              ),
            ),
          if (themeProvider.gamesEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildModuleToggle(
                context,
                'hangman_module',
                'hangman_module_desc',
                Icons.text_fields,
                themeProvider.hangmanEnabled,
                (value) => themeProvider.setHangmanEnabled(value),
                helpTopicId: 'hangman',
              ),
            ),
          if (themeProvider.gamificationEnabled && themeProvider.networkEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildModuleToggle(
                context,
                'network_gamification',
                'network_gamification_desc',
                Icons.leaderboard,
                themeProvider.networkGamificationEnabled,
                (value) => themeProvider.setNetworkGamificationEnabled(value),
                helpTopicId: 'network_gamification',
              ),
            ),
          if (themeProvider.networkGamificationEnabled &&
              themeProvider.gamificationEnabled &&
              themeProvider.networkEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: _buildModuleToggle(
                context,
                'share_gamification_stats',
                'share_gamification_stats_desc',
                Icons.share,
                themeProvider.shareGamificationStats,
                (value) => themeProvider.setShareGamificationStats(value),
                helpTopicId: 'share_gamification_stats',
              ),
            ),
          // === Group 2: Content & Library ===
          _buildModulesGroupHeader(context, 'modules_group_content'),
          _buildModuleToggle(
            context,
            'collections_module',
            'collections_module_desc',
            Icons.collections_bookmark,
            themeProvider.collectionsEnabled,
            (value) => themeProvider.setCollectionsEnabled(value),
            helpTopicId: 'collections',
          ),
          if (themeProvider.collectionsEnabled)
            _buildModuleToggle(
              context,
              'group_by_collections_title',
              'group_by_collections_desc',
              Icons.auto_stories,
              themeProvider.groupByCollections,
              (value) => themeProvider.setGroupByCollections(value),
              helpTopicId: 'group_by_collections',
            ),
          // The ownership axis of the library filter, as a
          // switch (ADR-063). On = "everything", off = the
          // possession default; the menu's third value, "not
          // owned", reads as off here and turning the switch
          // on from it lands on "everything", which is the
          // only value the switch promises.
          Consumer<OwnershipPreferenceProvider>(
            builder: (context, prefs, _) => _buildModuleToggle(
              context,
              'settings_show_not_owned_books',
              'settings_show_not_owned_books_desc',
              Icons.visibility_outlined,
              prefs.scope == OwnershipScope.all,
              (value) => prefs.setScope(value ? OwnershipScope.all : null),
            ),
          ),
          _buildModuleToggle(
            context,
            'carousel_peer_lib_title',
            'carousel_peer_lib_desc',
            Icons.new_releases,
            !themeProvider.carouselHiddenPeerLib,
            (value) => themeProvider.setCarouselHiddenPeerLib(!value),
          ),
          _buildModuleToggle(
            context,
            'commerce_module',
            'commerce_module_desc',
            Icons.storefront,
            themeProvider.commerceEnabled,
            (value) => themeProvider.setCommerceEnabled(value),
            helpTopicId: 'commerce_module',
          ),
          _buildModuleToggle(
            context,
            'audio_module',
            'audio_module_desc',
            Icons.headphones,
            themeProvider.audioEnabled,
            (value) => themeProvider.setAudioEnabled(value),
            helpTopicId: 'audio',
          ),
          _buildModuleToggle(
            context,
            'speech_to_text_setting',
            'speech_to_text_setting_desc',
            Icons.mic,
            themeProvider.speechToTextEnabled,
            (value) => themeProvider.setSpeechToTextEnabled(value),
            helpTopicId: 'speech_to_text',
          ),
          // === Group 3: Lending & Formats ===
          _buildModulesGroupHeader(context, 'modules_group_lending'),
          _buildModuleToggle(
            context,
            'auto_approve_loans_title',
            'auto_approve_loans_desc',
            Icons.auto_awesome,
            themeProvider.autoApproveLoanRequests,
            (value) => themeProvider.setAutoApproveLoanRequests(value),
            helpTopicId: 'auto_approve_loans',
          ),
          if (_loanSettingsLoaded) _buildLoanDurationSection(context),
          _buildModuleToggle(
            context,
            'enable_borrowing_module',
            'borrowing_module_desc',
            Icons.swap_horiz,
            themeProvider.canBorrowBooks,
            (value) => themeProvider.setCanBorrowBooks(value),
            helpTopicId: 'enable_borrowing',
          ),
          _buildModuleToggle(
            context,
            'enable_lending_module',
            'lending_module_desc',
            Icons.handshake_outlined,
            themeProvider.canLendBooks,
            (value) => themeProvider.setCanLendBooks(value),
            helpTopicId: 'enable_lending',
          ),
          if (themeProvider.networkEnabled)
            _buildModuleToggle(
              context,
              'settings_allow_private_books',
              'settings_allow_private_books_desc',
              Icons.visibility_off,
              themeProvider.allowPrivateBooks,
              (value) => themeProvider.setAllowPrivateBooks(value),
              helpTopicId: 'allow_private_books',
            ),
          _buildModuleToggle(
            context,
            'module_digital_formats',
            'module_digital_formats_desc',
            Icons.tablet_mac,
            themeProvider.digitalFormatsEnabled,
            (value) => themeProvider.setDigitalFormatsEnabled(value),
            helpTopicId: 'digital_formats',
          ),
          // === Group 4: Advanced ===
          _buildModulesGroupHeader(context, 'modules_group_advanced'),
          if (_coverScannerAvailable)
            _buildModuleToggle(
              context,
              'module_cover_auto_crop',
              // On Android the crop comes from Google Play
              // services, which the description says.
              io.Platform.isAndroid
                  ? 'module_cover_auto_crop_desc_android'
                  : 'module_cover_auto_crop_desc',
              Icons.crop,
              themeProvider.coverAutoCropEnabled,
              (value) => themeProvider.setCoverAutoCropEnabled(value),
            ),
          _buildMcpModuleToggle(),

          // Notifications section
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              TranslationService.translate(context, 'settings_notifications'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          _buildModuleToggle(
            context,
            'settings_notif_enabled',
            'settings_notif_enabled_desc',
            Icons.notifications_outlined,
            themeProvider.notificationsEnabled,
            (value) => themeProvider.setNotificationsEnabled(value),
            helpTopicId: 'notif_enabled',
          ),
          if (themeProvider.notificationsEnabled) ...[
            _buildModuleToggle(
              context,
              'settings_notif_connections',
              'settings_notif_connections_desc',
              Icons.people_outline,
              themeProvider.notifConnectionsEnabled,
              (value) => themeProvider.setNotifConnectionsEnabled(value),
              helpTopicId: 'notif_connections',
            ),
            _buildModuleToggle(
              context,
              'settings_notif_loans',
              'settings_notif_loans_desc',
              Icons.menu_book_outlined,
              themeProvider.notifLoansEnabled,
              (value) => themeProvider.setNotifLoansEnabled(value),
              helpTopicId: 'notif_loans',
            ),
            _buildModuleToggle(
              context,
              'settings_notif_discoveries',
              'settings_notif_discoveries_desc',
              Icons.explore_outlined,
              themeProvider.notifDiscoveriesEnabled,
              (value) => themeProvider.setNotifDiscoveriesEnabled(value),
              helpTopicId: 'notif_discoveries',
            ),
          ],

          // Developer Tools section
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              TranslationService.translate(
                    context,
                    'settings_developer_tools',
                  ) ??
                  'Developer Tools',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          _buildModuleToggle(
            context,
            'module_operation_log_viewer',
            'module_operation_log_desc',
            Icons.receipt_long_rounded,
            themeProvider.operationLogViewerEnabled,
            (value) => themeProvider.setOperationLogViewerEnabled(value),
          ),
          if (themeProvider.operationLogViewerEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.terminal_rounded),
                  title: Text(
                    TranslationService.translate(
                          context,
                          'admin_operation_log_title',
                        ) ??
                        'Operation Log',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  // push, not go: keeps the settings page under
                  // it so the log has a real back destination.
                  onTap: () => context.push('/operation-log'),
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SwitchListTile(
              secondary: const Icon(Icons.account_tree),
              title: Text(
                TranslationService.translate(context, 'enable_taxonomy') ??
                    'Hierarchical Tags',
              ),
              subtitle: const Text('Gestion de sous-étagères'),
              value: AppConstants.enableHierarchicalTags,
              onChanged: (bool value) async {
                setState(() {
                  AppConstants.enableHierarchicalTags = value;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('enableHierarchicalTags', value);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(
                              context,
                              'restart_required_for_changes',
                            ) ??
                            'Please restart the app for changes to take full effect',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLoanSettings() async {
    try {
      final ffi = FfiService();
      final settings = await ffi.getLoanSettings();
      if (mounted) {
        setState(() {
          _defaultLoanDurationDays = settings.defaultLoanDurationDays;
          _perBookDurationEnabled = settings.perBookDurationEnabled;
          _reminderDaysBeforeDue = settings.reminderDaysBeforeDue;
          _loanSettingsLoaded = true;
        });
      }
      return;
    } catch (e) {
      debugPrint('Error loading loan settings: $e');
    }
    // Show section with defaults even if FFI fails
    if (mounted) {
      setState(() => _loanSettingsLoaded = true);
    }
  }

  Widget _buildMcpModuleToggle() {
    if (!settingsMatches(context, ['mcp_integration', 'mcp_description'])) {
      return const SizedBox.shrink();
    }
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.extension),
                title: Text(
                  TranslationService.translate(context, 'mcp_integration') ??
                      'AI Assistants (MCP)',
                ),
                subtitle: Text(
                  TranslationService.translate(context, 'mcp_description') ??
                      'Connect your library to Claude, Cursor, and other AI assistants',
                ),
                value: theme.mcpEnabled,
                onChanged: (val) => theme.setMcpEnabled(val),
              ),
              if (theme.mcpEnabled && !kIsWeb) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyMcpConfig(),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(
                      TranslationService.translate(
                            context,
                            'copy_mcp_config',
                          ) ??
                          'Copy MCP Config',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Text(
                    TranslationService.translate(context, 'mcp_instructions') ??
                        'Paste this configuration into your AI assistant\'s settings file',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoanDurationSection(BuildContext context) {
    if (!settingsMatches(context, [
      'loan_duration_settings_title',
      'loan_duration_default_label',
      'loan_duration_per_book_toggle',
      'loan_reminder_days_label',
    ])) {
      return const SizedBox.shrink();
    }

    final daysLabel = TranslationService.translate(
      context,
      'loan_duration_days_suffix',
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Global default duration stepper
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'loan_duration_default_label',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'decrease_by_one',
                  ),
                  onPressed: _defaultLoanDurationDays > 1
                      ? () => _updateLoanDuration(_defaultLoanDurationDays - 1)
                      : null,
                ),
                GestureDetector(
                  onLongPress: () {
                    final newVal = (_defaultLoanDurationDays - 7).clamp(1, 365);
                    _updateLoanDuration(newVal);
                  },
                  child: SizedBox(
                    width: 80,
                    child: Text(
                      '$_defaultLoanDurationDays $daysLabel',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'increase_by_one',
                  ),
                  onPressed: _defaultLoanDurationDays < 365
                      ? () => _updateLoanDuration(_defaultLoanDurationDays + 1)
                      : null,
                ),
              ],
            ),
            const Divider(),
            // Per-book toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.auto_stories),
              title: Text(
                TranslationService.translate(
                  context,
                  'loan_duration_per_book_toggle',
                ),
              ),
              subtitle: Text(
                TranslationService.translate(
                  context,
                  'loan_duration_per_book_desc',
                ),
              ),
              value: _perBookDurationEnabled,
              onChanged: (value) => _updatePerBookToggle(value),
            ),
            const Divider(),
            // Reminder days stepper
            Row(
              children: [
                const Icon(Icons.notifications_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'loan_reminder_days_label',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'decrease_by_one',
                  ),
                  onPressed: _reminderDaysBeforeDue > 1
                      ? () => _updateReminderDays(_reminderDaysBeforeDue - 1)
                      : null,
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '$_reminderDaysBeforeDue $daysLabel',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'increase_by_one',
                  ),
                  onPressed: _reminderDaysBeforeDue < 10
                      ? () => _updateReminderDays(_reminderDaysBeforeDue + 1)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateLoanDuration(int days) async {
    setState(() => _defaultLoanDurationDays = days);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: days,
        perBookDurationEnabled: _perBookDurationEnabled,
        reminderDaysBeforeDue: _reminderDaysBeforeDue,
      );
    } catch (e) {
      debugPrint('Error updating loan duration: $e');
    }
  }

  Future<void> _updatePerBookToggle(bool enabled) async {
    setState(() => _perBookDurationEnabled = enabled);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: _defaultLoanDurationDays,
        perBookDurationEnabled: enabled,
        reminderDaysBeforeDue: _reminderDaysBeforeDue,
      );
    } catch (e) {
      debugPrint('Error updating per-book toggle: $e');
    }
  }

  Future<void> _updateReminderDays(int days) async {
    setState(() => _reminderDaysBeforeDue = days);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: _defaultLoanDurationDays,
        perBookDurationEnabled: _perBookDurationEnabled,
        reminderDaysBeforeDue: days,
      );
    } catch (e) {
      debugPrint('Error updating reminder days: $e');
    }
  }

  Widget _buildModulesGroupHeader(BuildContext context, String key) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(context, key) ?? '',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildModuleToggle(
    BuildContext context,
    String titleKey,
    String descKey,
    IconData icon,
    bool value,
    ValueChanged<bool>? onChanged, {
    String? tag,
    String? helpTopicId,
  }) {
    if (!settingsMatches(context, [titleKey, descKey])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Row(
          children: [
            Flexible(
              child: Text(TranslationService.translate(context, titleKey)),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            ],
            if (helpTopicId != null) ...[
              const SizedBox(width: 4),
              HelpAffordance(topicId: helpTopicId),
            ],
          ],
        ),
        subtitle: Text(TranslationService.translate(context, descKey)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _copyMcpConfig() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      // Fetch config from backend with dynamic paths
      final response = await apiService.getMcpConfig();

      if (response.statusCode == 200 && response.data != null) {
        // Use the config_json directly from the response
        final configJson = response.data['config_json'] as String? ?? '{}';

        await Clipboard.setData(ClipboardData(text: configJson));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'mcp_config_copied') ??
                    'MCP configuration copied to clipboard!',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to fetch MCP config');
      }
    } catch (e) {
      debugPrint('Error fetching MCP config: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching configuration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
