import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/contextual_help_sheet.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../theme/app_design.dart';
import '../widgets/account_sync_summary_sheet.dart';
import '../widgets/goal_tile.dart';
import 'settings/account_section.dart';
import 'settings/backup_section.dart';
import 'settings/languages_section.dart';
import 'settings/network_section.dart';
import 'settings/settings_scope.dart';
import 'settings/settings_sections.dart';
import 'settings/settings_widgets.dart';

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
  // What the sections share, loaded again on each open (see SettingsData).
  late final SettingsData _data;
  // Settings search
  String _settingsSearch = '';
  final _settingsSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = context.read<SettingsData>();
    // Shared with the section pages, it outlives this page: start this visit
    // from what the backend answers. No notification, nothing listens yet.
    _data.forgetVisit();
    _data.addListener(_onDataChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // After the frame: loading notifies the shared data's listeners, which
      // may be building.
      _fetchSettings();
      // Load hub directory config + preferences (non-blocking)
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

  @override
  void dispose() {
    _data.removeListener(_onDataChanged);
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
  /// widgets shown in the section pages. Lighter than a whole section page
  /// (only what the goal needs; dismiss with a swipe).
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

  /// Goal-oriented shortcuts (four at most) shown above the sections when the
  /// search box is empty. Each tile is phrased as something the user wants to
  /// DO (not a subsystem name), making capabilities discoverable without
  /// browsing the sections. Each opens a focused bottom sheet with the
  /// relevant capability, built from the widgets of its section.
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
        // "manage" variant (with a check badge) instead of disappearing.
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
              _buildGoalTile(
                context,
                icon: Icons.devices,
                labelKey: 'settings_goal_sync_devices',
                onTap: () => showAccountSyncSummarySheet(context),
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

                // Empty search: the shortcuts, then the list of sections.
                // A search stacks the matching sections instead, whatever
                // their group, each under a title that opens its page.
                if (!_isSearching) ...[
                  _buildSpringboard(context),
                  for (final group in settingsSectionGroups)
                    ..._buildSectionGroup(context, group),
                ] else
                  for (final group in settingsSectionGroups)
                    for (final section in group.sections)
                      // Remounted when a section page opened from here
                      // closes: they keep what they read when built.
                      section.builder(
                        key: ValueKey(
                          '${section.name}_section_${_data.resultsGeneration}',
                        ),
                      ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A group header, then a card listing the group's sections. Each entry
  /// opens the section's page.
  List<Widget> _buildSectionGroup(
    BuildContext context,
    SettingsSectionGroup group,
  ) {
    return [
      SettingsGroupHeader(group.titleKey),
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            for (final section in group.sections)
              ListTile(
                leading: Icon(section.icon),
                title: Text(
                  TranslationService.translate(context, section.titleKey),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/${section.name}'),
              ),
          ],
        ),
      ),
    ];
  }

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
}
