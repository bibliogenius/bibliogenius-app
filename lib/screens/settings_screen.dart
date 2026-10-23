import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/contextual_help_sheet.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_design.dart';
import '../utils/backup_actions.dart';
import '../widgets/account_sync_summary_sheet.dart';
import '../widgets/goal_tile.dart';
import 'settings/backup_section.dart';
import 'settings/bookshops_section.dart';
import 'settings/contact_details_section.dart';
import 'settings/content_section.dart';
import 'settings/languages_section.dart';
import 'settings/modules_section.dart';
import 'settings/network_section.dart';
import 'settings/search_sources_section.dart';
import 'settings/settings_scope.dart';
import 'settings/theme_section.dart';

class SettingsScreen extends StatefulWidget {
  /// When set (via `/settings?focus=...`), the matching capability bottom sheet
  /// is opened on arrival. Lets the Dashboard "discover more" tiles deep-link
  /// straight to a capability, reusing these sheets. Supported: 'wifi',
  /// 'public', 'backup', 'language'.
  final String? initialFocus;

  const SettingsScreen({super.key, this.initialFocus});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // What the sections share, loaded once on open (see SettingsData).
  final _data = SettingsData();
  String _appVersion = '';
  // Settings search
  String _settingsSearch = '';
  final _settingsSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data.addListener(_onDataChanged);
    _fetchSettings();
    _initPackageInfo();
    // Load hub directory config + preferences (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hubProvider = context.read<HubDirectoryProvider>();
      final themeProvider = context.read<ThemeProvider>();
      hubProvider.loadConfig().then((_) {
        // Ensure X25519 key is published on hub for E2EE contact sharing
        if (hubProvider.isRegistered) {
          hubProvider.ensureKeysPublished(themeProvider.libraryName);
        }
      });
      hubProvider.loadHubEnabled();
      hubProvider.loadShareCity();
      hubProvider.loadLocalCityId();
      // The contact card is loaded by ContactCardFields itself.
      hubProvider.loadWebsite().then((_) {
        if (mounted && _data.hubWebsiteController.text.isEmpty) {
          _data.hubWebsiteController.text = hubProvider.websiteUrl;
        }
      });
    });
    // Deep-link from the Dashboard "discover more" tiles: open the matching
    // capability sheet on arrival.
    if (widget.initialFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFocusSheet(widget.initialFocus!);
      });
    }
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the capability sheet matching a `/settings?focus=...` deep link.
  void _openFocusSheet(String focus) {
    switch (focus) {
      case 'wifi':
        _showCapabilitySheet(
          context,
          icon: Icons.wifi_tethering,
          titleKey: 'settings_goal_local_wifi',
          content: [const LocalNetworkCard()],
        );
      case 'public':
        _showCapabilitySheet(
          context,
          content: [const DirectorySettings(showPeerViewLink: true)],
        );
      case 'backup':
        _showBackupSheet(context);
      case 'language':
        _showCapabilitySheet(
          context,
          icon: Icons.translate,
          titleKey: 'settings_goal_language',
          content: [const ReadingLanguagesField()],
        );
    }
  }

  Future<void> _initPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version} (${info.buildNumber})';
        });
      }
    } catch (e) {
      debugPrint('Error getting package info: $e');
    }
  }

  @override
  void dispose() {
    _data.removeListener(_onDataChanged);
    _data.dispose();
    _settingsSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSettings() => _data.load(
    Provider.of<ApiService>(context, listen: false),
    Provider.of<ThemeProvider>(context, listen: false),
    context.read<HubDirectoryProvider>(),
  );

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return SettingsScope(
      data: _data,
      query: _settingsSearch,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GenieAppBar(
          title: TranslationService.translate(context, 'nav_settings'),
          leading: buildDrawerLeading(context),
          automaticallyImplyLeading: false,
          showQuickActions: false,
          actions: [
            ContextualHelpIconButton(
              titleKey: 'help_ctx_settings_title',
              contentKey: 'help_ctx_settings_content',
              tips: const [
                HelpTip(
                  icon: Icons.toggle_on,
                  color: Colors.blue,
                  titleKey: 'help_ctx_settings_tip_modules',
                  descriptionKey: 'help_ctx_settings_tip_modules_desc',
                ),
                HelpTip(
                  icon: Icons.backup,
                  color: Colors.green,
                  titleKey: 'help_ctx_settings_tip_backup',
                  descriptionKey: 'help_ctx_settings_tip_backup_desc',
                ),
                HelpTip(
                  icon: Icons.search,
                  color: Colors.orange,
                  titleKey: 'help_ctx_settings_tip_sources',
                  descriptionKey: 'help_ctx_settings_tip_sources_desc',
                ),
              ],
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
          ),
          child: SafeArea(
            child: _data.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                // Below the scope, so the content can match the search.
                : Builder(builder: _buildSettingsContent),
          ),
        ),
      ),
    );
  }

  bool get _isSearching => _settingsSearch.isNotEmpty;

  /// Opens a focused bottom sheet for a springboard capability: an optional
  /// goal-phrased title + the relevant toggle(s)/actions, reusing the same
  /// widgets shown in the settings accordions. Lighter and more reliable than
  /// navigating into the long accordion list (no scroll math; dismiss with a
  /// swipe).
  Future<void> _showCapabilitySheet(
    BuildContext context, {
    IconData? icon,
    String? titleKey,
    required List<Widget> content,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final sheet = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + media.viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titleKey != null) ...[
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            TranslationService.translate(
                              sheetContext,
                              titleKey,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                ...content,
              ],
            ),
          ),
        );
        return SettingsScope(data: _data, query: _settingsSearch, child: sheet);
      },
    );
  }

  /// Goal-oriented shortcuts shown above the presets when the search box is
  /// empty. Each tile is phrased as something the user wants to DO (not a
  /// subsystem name), making capabilities discoverable without spelunking the
  /// accordions. Tiles either push a dedicated screen or open a focused bottom
  /// sheet with the relevant capability.
  Widget _buildSpringboard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'settings_springboard_title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        // State-aware tiles: once a capability is enabled its tile flips to a
        // "manage" variant (with a check badge) instead of disappearing. The
        // city tile only appears once the library is listed publicly, since
        // sharing a city is meaningless without a public profile.
        Consumer2<HubDirectoryProvider, ThemeProvider>(
          builder: (context, hub, theme, _) {
            final tiles = <Widget>[
              // Backup goal: the sheet leads with the encrypted account (the
              // recommended safety net), then the local/offline actions.
              _buildGoalTile(
                context,
                icon: Icons.backup_outlined,
                labelKey: 'settings_goal_backup',
                onTap: () => _showBackupSheet(context),
              ),
              // Public directory (transform-in-place). Sheet keeps no title:
              // the directory section carries its own "Annuaire" header.
              _buildGoalTile(
                context,
                icon: Icons.public,
                labelKey: hub.isListed
                    ? 'settings_goal_manage_public'
                    : 'settings_goal_public',
                active: hub.isListed,
                onTap: () => _showCapabilitySheet(
                  context,
                  content: [const DirectorySettings(showPeerViewLink: true)],
                ),
              ),
              // Local Wi-Fi sharing (transform-in-place).
              _buildGoalTile(
                context,
                icon: Icons.wifi_tethering,
                labelKey: theme.networkEnabled
                    ? 'settings_goal_manage_wifi'
                    : 'settings_goal_local_wifi',
                active: theme.networkEnabled,
                onTap: () => _showCapabilitySheet(
                  context,
                  icon: Icons.wifi_tethering,
                  titleKey: theme.networkEnabled
                      ? 'settings_goal_manage_wifi'
                      : 'settings_goal_local_wifi',
                  content: [const LocalNetworkCard()],
                ),
              ),
              // Encrypted account, phrased as the one goal the backup tile
              // does not cover (multi-device reading). Opens a state-aware
              // summary sheet like the other goal tiles; the dedicated hub
              // screen stays the single management surface behind it.
              if (settingsMatches(context, [
                'settings_goal_sync_devices',
                'account_sync_title',
                'account_sync_settings_subtitle',
              ]))
                _buildGoalTile(
                  context,
                  icon: Icons.devices,
                  labelKey: 'settings_goal_sync_devices',
                  onTap: () => showAccountSyncSummarySheet(context),
                ),
              // Invitation to discover multi-language reading. Once the user
              // has more than one reading language the capability is discovered;
              // further tweaks live in Settings > Languages.
              if (theme.userLanguages.length <= 1)
                _buildGoalTile(
                  context,
                  icon: Icons.translate,
                  labelKey: 'settings_goal_language',
                  onTap: () => _showCapabilitySheet(
                    context,
                    icon: Icons.translate,
                    titleKey: 'settings_goal_language',
                    content: [const ReadingLanguagesField()],
                  ),
                ),
              // Country first: the city picker resolves its list from the
              // user's country file, so there is nothing to pick without one.
              if (hub.isListed && theme.country.isEmpty)
                _buildGoalTile(
                  context,
                  icon: Icons.flag_outlined,
                  labelKey: 'settings_goal_set_country',
                  onTap: () => _showCapabilitySheet(
                    context,
                    icon: Icons.flag_outlined,
                    titleKey: 'settings_goal_set_country',
                    content: [const CountryPickerField()],
                  ),
                ),
              // Then the city itself. Not gated on being listed: the city is
              // a local preference, and inviting only public profiles to fill
              // it in is what made it look like a directory feature. The tile
              // drops off once a city is set: a one-off setup, manageable
              // later from Settings > Languages.
              if (theme.country.isNotEmpty && hub.localCityId == null)
                _buildGoalTile(
                  context,
                  icon: Icons.location_city_outlined,
                  labelKey: 'settings_goal_set_city',
                  onTap: () => _showCapabilitySheet(
                    context,
                    icon: Icons.location_city_outlined,
                    titleKey: 'settings_goal_set_city',
                    content: [const CitySettings()],
                  ),
                ),
            ];
            return _buildTileGrid(tiles);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Lays out springboard tiles two per row. Plain Rows (no cross-axis stretch)
  /// to keep constraints bounded inside the scrolling Column.
  Widget _buildTileGrid(List<Widget> tiles) {
    // On narrow (mobile) screens, stack each tile full-width; only use two
    // columns when there is room (tablet/desktop). 600px matches the breakpoint
    // used elsewhere (e.g. the dashboard "Discover more" grid).
    final isWide = MediaQuery.of(context).size.width > 600;
    if (!isWide) {
      final rows = <Widget>[];
      for (final tile in tiles) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
        rows.add(tile);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        Row(
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 8),
            Expanded(
              child: i + 1 < tiles.length
                  ? tiles[i + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }

  /// Thin wrapper over the shared [GoalTile] that translates the label key.
  Widget _buildGoalTile(
    BuildContext context, {
    required IconData icon,
    required String labelKey,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GoalTile(
      icon: icon,
      label: TranslationService.translate(context, labelKey),
      onTap: onTap,
      active: active,
    );
  }

  Widget _buildSettingsContent(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final hasPassword = _data.userInfo?['has_password'] ?? false;

    return RefreshIndicator(
      onRefresh: _fetchSettings,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDesign.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar
                TextField(
                  controller: _settingsSearchController,
                  decoration: InputDecoration(
                    hintText: TranslationService.translate(
                      context,
                      'settings_search_hint',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _settingsSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: TranslationService.translate(
                              context,
                              'action_clear',
                            ),
                            onPressed: () {
                              _settingsSearchController.clear();
                              setState(() => _settingsSearch = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _settingsSearch = v),
                  // Drop the keyboard as soon as a tile is tapped. A tile that
                  // presents a native sheet (file picker, share sheet) over a
                  // still-focused field leaves iOS with a keyboard whose
                  // Flutter client is gone: it stays up and the done key is
                  // inert.
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                const SizedBox(height: 16),

                // Common-search shortcuts (hidden during search)
                if (!_isSearching) _buildSpringboard(context),

                // Quick Presets Section (hidden during search)
                if (!_isSearching) ...[
                  Text(
                    TranslationService.translate(context, 'quick_presets') ??
                        'Quick Presets',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.translate(
                          context,
                          'quick_presets_desc',
                        ) ??
                        'Apply a configuration adapted to your usage:',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPresetButton(
                          context,
                          'reader',
                          TranslationService.translate(
                                context,
                                'preset_reader',
                              ) ??
                              'Reader',
                          Icons.menu_book,
                          Colors.teal,
                          themeProvider,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPresetButton(
                          context,
                          'librarian',
                          TranslationService.translate(
                                context,
                                'preset_librarian',
                              ) ??
                              'Librarian',
                          Icons.local_library,
                          Colors.indigo,
                          themeProvider,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPresetButton(
                          context,
                          'bookseller',
                          TranslationService.translate(
                                context,
                                'preset_bookseller',
                              ) ??
                              'Bookseller',
                          Icons.storefront,
                          Colors.orange,
                          themeProvider,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Each section is keyed: the springboard and the presets leave the
                // column while searching, and the sections must keep their state
                // (loan settings, peer cover cache size) across that shift.
                const ContactDetailsSettingsSection(
                  key: ValueKey('contact_details_section'),
                ),

                const ContentSettingsSection(key: ValueKey('content_section')),

                const BackupSettingsSection(key: ValueKey('backup_section')),
                const ThemeSettingsSection(key: ValueKey('theme_section')),

                const LanguagesSettingsSection(
                  key: ValueKey('languages_section'),
                ),

                const ModulesSettingsSection(key: ValueKey('modules_section')),

                const NetworkSettingsSection(key: ValueKey('network_section')),

                // (Multi-device account sync moved to the "Que voulez-vous faire ?"
                // springboard tile above so it is reachable without scrolling.)
                const SearchSourcesSettingsSection(
                  key: ValueKey('search_sources_section'),
                ),

                const BookshopsSettingsSection(
                  key: ValueKey('bookshops_section'),
                ),

                const SizedBox(height: 24),

                // Session / Logout (only shown for authenticated users)
                if (hasPassword)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final authService = Provider.of<AuthService>(
                        context,
                        listen: false,
                      );
                      await Future.delayed(const Duration(milliseconds: 200));
                      await authService.logout();
                      if (mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: Text(
                      TranslationService.translate(context, 'logout'),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      foregroundColor: Colors.red,
                    ),
                  ),
                if (settingsMatches(context, [
                  'system_reset_title',
                  'system_reset_subtitle',
                ])) ...[
                  const SizedBox(height: 32),
                  Card(
                    margin: EdgeInsets.zero,
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_forever,
                        color: Colors.red.shade700,
                      ),
                      title: Text(
                        TranslationService.translate(
                          context,
                          'system_reset_title',
                        ),
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                          context,
                          'system_reset_subtitle',
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Colors.red.shade700,
                      ),
                      onTap: () => BackupActions.showResetDialog(context),
                    ),
                  ),
                ],
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      'BiblioGenius v$_appVersion',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Unified Network section
  // ---------------------------------------------------------------------------

  /// Backup capability sheet (springboard tile + dashboard deep-link): the
  /// encrypted account leads as the recommended safety net, then the
  /// local/offline actions follow unchanged. Tapping the account tile swaps
  /// the sheet content to the account summary IN PLACE (with a back row)
  /// instead of stacking the hub screen on top of the popin. Opt-in, never
  /// forced: the no-account path stays fully available below the divider.
  Future<void> _showBackupSheet(BuildContext context) {
    var showAccount = false;
    return _showCapabilitySheet(
      context,
      content: [
        StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            if (showAccount) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        TranslationService.translate(
                          sheetContext,
                          'settings_goal_backup',
                        ),
                      ),
                      onPressed: () => setSheetState(() => showAccount = false),
                    ),
                  ),
                  const AccountSyncSummaryBody(
                    titleKey: 'account_sync_title',
                    icon: Icons.lock_outline,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.backup_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          TranslationService.translate(
                            sheetContext,
                            'settings_goal_backup',
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AccountSyncTile(
                  onTap: () => setSheetState(() => showAccount = true),
                ),
                ...offlineDividerWidgets(sheetContext),
                ...backupActionTiles(sheetContext),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Public Directory section
  // ---------------------------------------------------------------------------

  // _buildAcceptFromSelector removed (dead code: hub ignores these values)

  Widget _buildPresetButton(
    BuildContext context,
    String presetName,
    String label,
    IconData icon,
    Color color,
    ThemeProvider themeProvider,
  ) {
    return Semantics(
      // Applies the preset at once: an action, so a button.
      button: true,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await themeProvider.applyPreset(presetName);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${TranslationService.translate(context, 'preset_applied') ?? 'Configuration applied'}: $label',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // All available reading languages with native names (shared constant)

  // _buildRelayHubCard removed - relay details now inline in _buildRelayDetails
}
