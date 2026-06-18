import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, kReleaseMode;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:country_picker/country_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/genie_app_bar.dart';
import '../widgets/peer_book_cover_cache_manager.dart';
import '../widgets/recovery_code_widgets.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/contextual_help_sheet.dart';
import '../services/api_service.dart';
import '../services/city_repository.dart';
import '../services/translation_service.dart';
import '../widgets/city_picker_sheet.dart';
import '../providers/theme_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../services/auth_service.dart';
import '../services/ffi_service.dart';
import '../services/mdns_service.dart';
import '../theme/app_design.dart';
import '../themes/base/theme_registry.dart';
import '../utils/app_constants.dart';
import '../utils/backup_actions.dart';
import '../utils/import_actions.dart';
import '../widgets/auto_backup_status_card.dart';
import '../src/rust/api/frb.dart' as rust;
import 'backup_restore_wizard_screen.dart';
import '../utils/language_constants.dart';
import '../utils/settings_search.dart';
import '../widgets/goal_tile.dart';

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
  bool _isLoading = true;
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _userStatus;
  Map<String, bool> _searchPrefs = {};
  String _googleBooksApiKey = '';
  // Reveal state for the Google Books API key field (replaces a nested
  // ExpansionTile that crashed layout; see _buildSearchConfiguration).
  bool _showGoogleAdvanced = false;
  String _appVersion = '';
  final _apiKeyController = TextEditingController();
  // Loan settings
  int _defaultLoanDurationDays = 21;
  bool _perBookDurationEnabled = false;
  int _reminderDaysBeforeDue = 2;
  bool _loanSettingsLoaded = false;
  // Relay Hub state
  String? _relayMailboxUuid;
  bool _relayConnected = false;
  bool _relayLoading = false;
  final _relayUrlController = TextEditingController();
  // Hub directory contact + website controllers
  final _hubContactController = TextEditingController();
  final _hubWebsiteController = TextEditingController();
  // Settings search
  String _settingsSearch = '';
  final _settingsSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSettings();
    _initPackageInfo();
    _loadLoanSettings();
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
      hubProvider.loadContactInfo().then((_) {
        if (mounted && _hubContactController.text.isEmpty) {
          _hubContactController.text = hubProvider.contactInfo;
        }
      });
      hubProvider.loadWebsite().then((_) {
        if (mounted && _hubWebsiteController.text.isEmpty) {
          _hubWebsiteController.text = hubProvider.websiteUrl;
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

  /// Opens the capability sheet matching a `/settings?focus=...` deep link.
  void _openFocusSheet(String focus) {
    switch (focus) {
      case 'wifi':
        _showCapabilitySheet(
          context,
          icon: Icons.wifi_tethering,
          titleKey: 'settings_goal_local_wifi',
          content: [_buildLocalNetworkCard(context)],
        );
      case 'public':
        _showCapabilitySheet(
          context,
          content: [_buildDirectorySection(context)],
        );
      case 'backup':
        _showCapabilitySheet(
          context,
          icon: Icons.backup_outlined,
          titleKey: 'settings_goal_backup',
          content: _backupChildren(context),
        );
      case 'language':
        _showCapabilitySheet(
          context,
          icon: Icons.translate,
          titleKey: 'settings_goal_language',
          content: [_buildReadingLanguagesField(context)],
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
    _apiKeyController.dispose();
    _relayUrlController.dispose();
    _hubContactController.dispose();
    _hubWebsiteController.dispose();
    _settingsSearchController.dispose();
    super.dispose();
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

  Future<void> _fetchSettings() async {
    final api = Provider.of<ApiService>(context, listen: false);

    setState(() => _isLoading = true);

    try {
      // Fetch Config
      final configRes = await api.getLibraryConfig();
      if (configRes.statusCode == 200) {
        _config = configRes.data;
        // Library name is managed by ThemeProvider (SharedPreferences + FFI).
        // Profile type is no longer synced — module toggles drive UI now.
      }

      // Fetch User Info
      final meRes = await api.getMe();
      if (meRes.statusCode == 200) {
        _userInfo = meRes.data;
      }

      // Fetch User Status for search preferences
      final statusRes = await api.getUserStatus();
      if (statusRes.statusCode == 200) {
        _userStatus = statusRes.data;
        if (_userStatus != null && _userStatus!['config'] != null) {
          final config = _userStatus!['config'];
          if (config['fallback_preferences'] != null) {
            final prefs = config['fallback_preferences'] as Map;
            prefs.forEach((key, value) {
              if (value is bool) {
                _searchPrefs[key.toString()] = value;
              }
            });
          }
          if (config['api_keys'] != null && config['api_keys'] is Map) {
            final apiKeys = config['api_keys'] as Map;
            _googleBooksApiKey = apiKeys['google_books']?.toString() ?? '';
            _apiKeyController.text = _googleBooksApiKey;
            if (_googleBooksApiKey.isNotEmpty) _showGoogleAdvanced = true;
          }
        }
      }

      // FFI mode: getUserStatus is mapped from gamification_get_status, which
      // does not carry search preferences. Hydrate them from a dedicated FFI
      // call so the toggles reflect the persisted state on screen open.
      if (api.useFfi) {
        try {
          final settings = await FfiService().getSearchSettings();
          settings.fallbackPreferences.forEach((key, value) {
            _searchPrefs[key] = value;
          });
          final googleKey = settings.apiKeys['google_books'] ?? '';
          if (googleKey.isNotEmpty) {
            _googleBooksApiKey = googleKey;
            _apiKeyController.text = googleKey;
            _showGoogleAdvanced = true;
          }
        } catch (e) {
          debugPrint('FFI getSearchSettings failed: $e');
        }
      }

      // Load relay config (may have been auto-configured at startup)
      try {
        final relayRes = await api.getRelayConfig();
        if (relayRes.statusCode == 200 &&
            relayRes.data is Map &&
            relayRes.data['relay_url'] != null) {
          _relayConnected = true;
          _relayMailboxUuid = relayRes.data['mailbox_uuid'] as String?;
          _relayUrlController.text =
              relayRes.data['relay_url'] as String? ?? '';
        } else {
          _relayUrlController.text = ApiService.hubUrl;
          // Auto-connect relay if remote reachable is enabled but not yet connected
          final themeProvider = Provider.of<ThemeProvider>(
            context,
            listen: false,
          );
          if (themeProvider.remoteReachableEnabled) {
            _autoConnectRelay();
          }
        }
      } catch (_) {
        _relayUrlController.text = ApiService.hubUrl;
      }

      // Loan settings loaded separately in _loadLoanSettings()

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching settings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : _buildSettingsContent(context),
        ),
      ),
    );
  }

  /// Returns true if any of the given i18n keys' translated text contains the search query.
  bool _matchesSearch(List<String> keys) {
    if (_settingsSearch.isEmpty) return true;
    for (final key in keys) {
      if (settingsKeyMatches(
        key: key,
        label: TranslationService.translate(context, key),
        query: _settingsSearch,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Whether a section should be visible during search.
  /// Pass the section title key + all toggle keys inside the section.
  bool _sectionVisible(List<String> keys) {
    if (_settingsSearch.isEmpty) return true;
    return _matchesSearch(keys);
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
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + media.viewInsets.bottom),
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
                            TranslationService.translate(sheetContext, titleKey),
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
              _buildGoalTile(
                context,
                icon: Icons.devices_rounded,
                labelKey: 'settings_goal_sync_devices',
                onTap: () => context.push('/device-pairing'),
              ),
              _buildGoalTile(
                context,
                icon: Icons.backup_outlined,
                labelKey: 'settings_goal_backup',
                onTap: () => _showCapabilitySheet(
                  context,
                  icon: Icons.backup_outlined,
                  titleKey: 'settings_goal_backup',
                  content: _backupChildren(context),
                ),
              ),
              // Public directory (transform-in-place). Sheet keeps no title:
              // the directory section carries its own "Annuaire public" header.
              _buildGoalTile(
                context,
                icon: Icons.public,
                labelKey: hub.isListed
                    ? 'settings_goal_manage_public'
                    : 'settings_goal_public',
                active: hub.isListed,
                onTap: () => _showCapabilitySheet(
                  context,
                  content: [_buildDirectorySection(context)],
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
                  content: [_buildLocalNetworkCard(context)],
                ),
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
                    content: [_buildReadingLanguagesField(context)],
                  ),
                ),
              // City surfaces only once the library is listed. The city picker
              // resolves cities from the user's country, so require a country
              // first ("Renseigner mon pays" otherwise). Once the city is
              // actually shared the tile drops off entirely — it's a one-off
              // setup, manageable later from Settings > Languages.
              if (hub.isListed && theme.country.isEmpty)
                _buildGoalTile(
                  context,
                  icon: Icons.flag_outlined,
                  labelKey: 'settings_goal_set_country',
                  onTap: () => _showCapabilitySheet(
                    context,
                    icon: Icons.flag_outlined,
                    titleKey: 'settings_goal_set_country',
                    content: [_buildCountryPicker(context, theme)],
                  ),
                ),
              if (hub.isListed &&
                  theme.country.isNotEmpty &&
                  !hub.isShareCityEnabled)
                _buildGoalTile(
                  context,
                  icon: Icons.location_city_outlined,
                  labelKey: 'settings_share_city',
                  onTap: () => _showCapabilitySheet(
                    context,
                    icon: Icons.location_city_outlined,
                    titleKey: 'settings_share_city',
                    content: [_buildCitySection(context, theme)],
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
    final hasPassword = _userInfo?['has_password'] ?? false;
    final mfaEnabled = _userInfo?['mfa_enabled'] ?? false;

    return RefreshIndicator(
      onRefresh: _fetchSettings,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
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
                TranslationService.translate(context, 'quick_presets_desc') ??
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
                      TranslationService.translate(context, 'preset_reader') ??
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

            // Data Management
            // Content accordion
            if (_sectionVisible([
              'content',
              'migration_card_csv_title',
              'migration_card_shelves_title',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('content_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'content'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.import_contacts,
                        color: Colors.orange.shade400,
                      ),
                      title: Text(
                        TranslationService.translate(
                          context,
                          'migration_card_csv_title',
                        ),
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                          context,
                          'migration_card_csv_subtitle',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ImportActions.importCsv(context),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.folder_special,
                        color: Colors.blue.shade400,
                      ),
                      title: Text(
                        TranslationService.translate(
                          context,
                          'migration_card_shelves_title',
                        ),
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                          context,
                          'migration_card_shelves_subtitle',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/shelves-management'),
                    ),
                  ],
                ),
              ),

            // Backup and export accordion (catalog JSON + future full backup + restore)
            if (_sectionVisible([
              'backup_section_title',
              'backup_export_catalog_title',
              'backup_full_title',
              'backup_restore_title',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('backup_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.backup_outlined),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'backup_section_title',
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: _backupChildren(context),
                ),
              ),

            // Account accordion (security + session)
            if (_sectionVisible([
              'account',
              'password',
              'two_factor_auth',
              'recovery_code_title',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('account_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.person_outlined),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'account'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: Text(
                        TranslationService.translate(context, 'password') ??
                            'Password',
                      ),
                      subtitle: Text(
                        hasPassword
                            ? '********'
                            : (TranslationService.translate(
                                    context,
                                    'not_set',
                                  ) ??
                                  'Not set'),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HelpAffordance(topicId: 'password_setting'),
                          TextButton(
                            onPressed: _showChangePasswordDialog,
                            child: Text(
                              TranslationService.translate(context, 'change') ??
                                  'Change',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Provider.of<ApiService>(context, listen: false).useFfi
                              ? (TranslationService.translate(
                                      context,
                                      'password_hint_local',
                                    ) ??
                                    'Optional. Protects access to your library when the app starts.')
                              : (TranslationService.translate(
                                      context,
                                      'password_hint_server',
                                    ) ??
                                    'Used to authenticate to the BiblioGenius server.'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!Provider.of<ApiService>(context, listen: false).useFfi)
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: Text(
                          TranslationService.translate(
                                context,
                                'two_factor_auth',
                              ) ??
                              'Two-Factor Authentication',
                        ),
                        subtitle: Text(
                          mfaEnabled
                              ? (TranslationService.translate(
                                      context,
                                      'enabled',
                                    ) ??
                                    'Enabled')
                              : (TranslationService.translate(
                                      context,
                                      'disabled',
                                    ) ??
                                    'Disabled'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const HelpAffordance(
                              topicId: 'two_factor_auth_setting',
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: mfaEnabled,
                              onChanged: (val) {
                                if (val) {
                                  _setupMfa();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    Consumer<HubDirectoryProvider>(
                      builder: (context, dirProvider, _) {
                        final config = dirProvider.config;
                        if (config == null) {
                          // Not registered (or config purged): offer manual
                          // reclaim with a previously-saved recovery code.
                          return Column(
                            children: [
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.restore),
                                title: Text(
                                  TranslationService.translate(
                                        context,
                                        'recovery_reclaim_title',
                                      ) ??
                                      'Reclaim profile with recovery code',
                                ),
                                subtitle: Text(
                                  TranslationService.translate(
                                        context,
                                        'recovery_reclaim_subtitle',
                                      ) ??
                                      'Use your saved recovery code to restore an existing profile',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final ok = await showRecoveryCodeInputSheet(
                                    context,
                                    dirProvider,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? (TranslationService.translate(
                                                    context,
                                                    'recovery_reclaim_success',
                                                  ) ??
                                                  'Profile reclaimed successfully')
                                            : (TranslationService.translate(
                                                    context,
                                                    'recovery_reclaim_failed',
                                                  ) ??
                                                  'Could not reclaim profile. Check the code and try again.'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.key),
                              title: Row(
                                children: [
                                  Text(
                                    TranslationService.translate(
                                          context,
                                          'recovery_code_title',
                                        ) ??
                                        'Recovery code',
                                  ),
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(
                                      TranslationService.translate(
                                            context,
                                            'badge_experimental',
                                          ) ??
                                          'Experimental',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide.none,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.tertiaryContainer,
                                    labelStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                TranslationService.translate(
                                      context,
                                      'recovery_code_subtitle',
                                    ) ??
                                    'Recover your profile after reinstalling the app',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final code = await dirProvider
                                    .getRecoveryCode();
                                if (!context.mounted) return;
                                if (code != null) {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (_) => RecoveryCodeDisplaySheet(
                                      recoveryCode: code,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        TranslationService.translate(
                                              context,
                                              'recovery_code_not_available',
                                            ) ??
                                            'Not available. Re-register to generate one.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            // Theme accordion (theme + text size)
            if (_sectionVisible([
              'theme_title',
              'nav_style_label',
              'nav_style_side_menu',
              'nav_style_bottom_bar',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('theme_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.palette_outlined),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'theme_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildThemeSelector(context, themeProvider),
                          const SizedBox(height: 24),
                          _buildTextScaleSlider(context, themeProvider),
                          const SizedBox(height: 24),
                          _buildNavStyleSelector(context, themeProvider),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Languages accordion
            if (_sectionVisible([
              'languages_section',
              'languages_reading',
              'languages_ui',
              'settings_country',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('languages_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.translate),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'languages_section',
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildLanguageSection(context, themeProvider),
                    ),
                  ],
                ),
              ),

            // Modules accordion
            if (_sectionVisible([
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
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('modules_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.extension_outlined),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'modules'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    // === Group 1: Reading & Fun ===
                    _buildModulesGroupHeader(
                      context,
                      'modules_group_reading_fun',
                    ),
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
                          (value) =>
                              themeProvider.setSlidingPuzzleEnabled(value),
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
                    if (themeProvider.gamificationEnabled &&
                        themeProvider.networkEnabled)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: _buildModuleToggle(
                          context,
                          'network_gamification',
                          'network_gamification_desc',
                          Icons.leaderboard,
                          themeProvider.networkGamificationEnabled,
                          (value) => themeProvider
                              .setNetworkGamificationEnabled(value),
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
                          (value) =>
                              themeProvider.setShareGamificationStats(value),
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
                    _buildModuleToggle(
                      context,
                      'carousel_own_lib_title',
                      'carousel_own_lib_desc',
                      Icons.new_releases_outlined,
                      !themeProvider.carouselHiddenOwnLib,
                      (value) => themeProvider.setCarouselHiddenOwnLib(!value),
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
                      (value) =>
                          themeProvider.setAutoApproveLoanRequests(value),
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
                    _buildMcpModuleToggle(),
                    // Linked Devices section
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        TranslationService.translate(
                          context,
                          'settings_linked_devices',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: ListTile(
                        leading: const Icon(Icons.devices_rounded),
                        title: Text(
                          TranslationService.translate(
                            context,
                            'settings_linked_devices',
                          ),
                        ),
                        subtitle: Text(
                          TranslationService.translate(
                            context,
                            'settings_linked_devices_desc',
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            HelpAffordance(topicId: 'device_sync'),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => context.push('/device-pairing'),
                      ),
                    ),

                    _buildModuleToggle(
                      context,
                      'settings_auto_backup',
                      'settings_auto_backup_desc',
                      Icons.backup_outlined,
                      themeProvider.autoBackupEnabled,
                      (value) => themeProvider.setAutoBackupEnabled(value),
                      helpTopicId: 'auto_backup',
                    ),

                    // Notifications section
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        TranslationService.translate(
                          context,
                          'settings_notifications',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
                        (value) =>
                            themeProvider.setNotifConnectionsEnabled(value),
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
                        (value) =>
                            themeProvider.setNotifDiscoveriesEnabled(value),
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildModuleToggle(
                      context,
                      'module_operation_log_viewer',
                      'module_operation_log_desc',
                      Icons.receipt_long_rounded,
                      themeProvider.operationLogViewerEnabled,
                      (value) =>
                          themeProvider.setOperationLogViewerEnabled(value),
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
                            onTap: () => context.go('/operation-log'),
                          ),
                        ),
                      ),
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SwitchListTile(
                        secondary: const Icon(Icons.account_tree),
                        title: Text(
                          TranslationService.translate(
                                context,
                                'enable_taxonomy',
                              ) ??
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
              ),

            // Network accordion (local + remote reachability + public directory)
            if (_sectionVisible([
              'settings_network_title',
              'settings_remote_reachable',
              'settings_remote_reachable_desc',
              'hub_coming_soon_toggle',
              'directory_settings_title',
              'directory_listed_title',
            ]))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('network_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.wifi),
                  title: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'settings_network_title',
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildNetworkSection(context, themeProvider),
                          const SizedBox(height: 12),
                          _buildDirectorySection(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Search Sources accordion
            if (_sectionVisible(['search_sources']))
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('search_sources_$_isSearching'),
                  initiallyExpanded: _isSearching,
                  leading: const Icon(Icons.saved_search),
                  title: Row(
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          TranslationService.translate(
                            context,
                            'search_sources',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const HelpAffordance(topicId: 'search_sources'),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildSearchConfiguration(context),
                    ),
                  ],
                ),
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
                label: Text(TranslationService.translate(context, 'logout')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  foregroundColor: Colors.red,
                ),
              ),
            if (_sectionVisible([
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
    );
  }

  // ---------------------------------------------------------------------------
  // Unified Network section
  // ---------------------------------------------------------------------------

  Widget _buildNetworkSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    String t(String key) => TranslationService.translate(context, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Explanation card ---
        _buildSharingModesCard(context, t),

        // --- Remote reachability (relay) ---
        Semantics(
          header: true,
          child: Text(
            t('settings_remote_reachable'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: Text(t('settings_remote_reachable')),
                subtitle: Text(t('settings_remote_reachable_desc')),
                value: themeProvider.remoteReachableEnabled,
                onChanged: (value) async {
                  await themeProvider.setRemoteReachableEnabled(value);
                  if (value) {
                    _autoConnectRelay();
                  }
                },
              ),
              if (themeProvider.remoteReachableEnabled) ...[
                const Divider(height: 1),
                ExpansionTile(
                  leading: const Icon(Icons.tune, size: 20),
                  title: Text(
                    t('settings_remote_reachable_details'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  children: [_buildRelayDetails(context)],
                ),
              ],
            ],
          ),
        ),

        // --- Local network sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_network_local'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        _buildLocalNetworkCard(context),

        // Extended network (public directory) hidden until feature is ready

        // --- Privacy & cache sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_network_privacy'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Consumer<HubDirectoryProvider>(
          builder: (context, dirProvider, _) {
            final isHubActive = dirProvider.config?.isListed ?? false;
            final anyNetworkActive =
                themeProvider.networkEnabled ||
                isHubActive ||
                themeProvider.remoteReachableEnabled;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  if (anyNetworkActive) ...[
                    SwitchListTile(
                      secondary: const Icon(Icons.cloud_off),
                      title: Text(t('peer_offline_caching')),
                      subtitle: Text(t('peer_offline_caching_desc')),
                      value: themeProvider.peerOfflineCachingEnabled,
                      onChanged: (value) =>
                          themeProvider.setPeerOfflineCachingEnabled(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.share),
                      title: Text(t('allow_library_caching')),
                      subtitle: Text(t('allow_library_caching_desc')),
                      value: themeProvider.allowLibraryCaching,
                      onChanged: (value) =>
                          themeProvider.setAllowLibraryCaching(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user),
                      title: Text(t('connection_validation')),
                      subtitle: Text(t('connection_validation_desc')),
                      value: themeProvider.connectionValidationEnabled,
                      onChanged: (value) =>
                          themeProvider.setConnectionValidationEnabled(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(
                        themeProvider.showViewCount
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      title: Text(t('show_view_count')),
                      subtitle: Text(t('show_view_count_desc')),
                      value: themeProvider.showViewCount,
                      onChanged: (value) =>
                          themeProvider.setShowViewCount(value),
                    ),
                  ],
                  if (!anyNetworkActive)
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: Colors.grey[400],
                      ),
                      title: Text(
                        t('settings_network_enable_first'),
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        // --- Peer book covers sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_peer_covers_section'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        _buildPeerCoverCoversCard(context, themeProvider, t),
      ],
    );
  }

  /// Local bump that invalidates the size-indicator FutureBuilder after an
  /// action that changes on-disk usage (cap change triggers a sweep, or
  /// the user hits Clear). Using a Key instead of caching the Future lets
  /// us stay with a StatelessWidget-shaped build while still forcing a
  /// fresh diskSizeBytes() read.
  int _peerCoverSizeNonce = 0;

  Widget _buildPeerCoverCoversCard(
    BuildContext context,
    ThemeProvider themeProvider,
    String Function(String) t,
  ) {
    final theme = Theme.of(context);
    final capMb = themeProvider.peerCoverCacheCapMb;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: Text(t('peer_cover_display_enabled')),
            subtitle: Text(t('peer_cover_display_enabled_desc')),
            value: themeProvider.peerCoverDisplayEnabled,
            onChanged: (value) =>
                themeProvider.setPeerCoverDisplayEnabled(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(t('peer_cover_cache_cap')),
            subtitle: Text(t('peer_cover_cache_cap_desc')),
            trailing: DropdownButton<int>(
              value: capMb,
              // Announce the currently-selected cap to screen readers on
              // focus, otherwise the raw "100 MB" label gives no context.
              items: ThemeProvider.peerCoverCacheCapChoicesMb
                  .map(
                    (mb) =>
                        DropdownMenuItem<int>(value: mb, child: Text('$mb MB')),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await themeProvider.setPeerCoverCacheCapMb(value);
                // Setter runs the disk sweep; our indicator needs a fresh
                // read so the displayed usage reflects any purge.
                if (mounted) {
                  setState(() => _peerCoverSizeNonce++);
                }
              },
            ),
          ),
          const Divider(height: 1),
          FutureBuilder<int>(
            key: ValueKey(_peerCoverSizeNonce),
            future: PeerBookCoverCacheManager.diskSizeBytes(),
            builder: (context, snapshot) {
              final usedMb = snapshot.hasData
                  ? (snapshot.data! / (1024 * 1024)).toStringAsFixed(1)
                  : '...';
              final usageText = TranslationService.translate(
                context,
                'peer_cover_cache_usage',
                params: {'used': usedMb, 'cap': '$capMb'},
              );
              return ListTile(
                leading: const Icon(Icons.data_usage_outlined),
                title: Text(t('peer_cover_cache_usage_title')),
                subtitle: Text(usageText),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: t('peer_cover_cache_refresh'),
                  onPressed: () => setState(() => _peerCoverSizeNonce++),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(
              t('peer_cover_cache_clear'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmClearPeerCoverCache(t),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearPeerCoverCache(String Function(String) t) async {
    // Capture the messenger before any await so the post-clear snackbar
    // is routed to the right Scaffold even if the user navigates away.
    final messenger = ScaffoldMessenger.of(context);
    final confirmLabel = t('peer_cover_cache_clear_done');
    final confirmed = await _confirmDestructiveAction(
      context,
      titleKey: 'peer_cover_cache_clear_title',
      titleFallback: 'Clear peer cover cache?',
      bodyKey: 'peer_cover_cache_clear_body',
      bodyFallback:
          'This deletes covers downloaded from peer libraries. '
          'Your own library covers are not affected.',
      actionKey: 'peer_cover_cache_clear_action',
      actionFallback: 'Clear',
    );
    if (!confirmed) return;
    await PeerBookCoverCacheManager.clearAll();
    if (!mounted) return;
    setState(() => _peerCoverSizeNonce++);
    messenger.showSnackBar(
      SnackBar(
        content: Text(confirmLabel),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Backup section content (status card + export/restore actions). Shared
  /// between the Backup accordion and the springboard "Sauvegarder ma
  /// bibliothèque" bottom sheet.
  List<Widget> _backupChildren(BuildContext context) {
    return [
      // Auto-backup status (ADR-037 §6) sits at the top so the green/amber/red
      // state is the first thing the user sees.
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AutoBackupStatusCard(),
      ),
      ListTile(
        leading: const Icon(Icons.backup, color: Colors.green),
        title: Text(
          TranslationService.translate(context, 'backup_export_catalog_title'),
        ),
        subtitle: Text(
          TranslationService.translate(
            context,
            'backup_export_catalog_subtitle',
          ),
        ),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HelpAffordance(topicId: 'backup_export_catalog'),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => BackupActions.exportCatalogJson(context),
      ),
      // Sauvegarde complète (.bgbackup, ADR-037 §2 writer).
      ListTile(
        leading: const Icon(Icons.shield_outlined, color: Colors.green),
        title: Text(
          TranslationService.translate(context, 'backup_full_title'),
        ),
        subtitle: Text(
          TranslationService.translate(context, 'backup_full_subtitle'),
        ),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HelpAffordance(topicId: 'backup_full'),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => BackupActions.runFullBackup(context),
      ),
      // Restauration .bgbackup (ADR-037 §5 reader).
      ListTile(
        leading: const Icon(Icons.shield, color: Colors.green),
        title: Text(
          TranslationService.translate(context, 'backup_restore_full_title'),
        ),
        subtitle: Text(
          TranslationService.translate(context, 'backup_restore_full_subtitle'),
        ),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HelpAffordance(topicId: 'backup_restore_full'),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const BackupRestoreWizardScreen(),
          ),
        ),
      ),
      // Restaurer mon catalogue (JSON, legacy).
      ListTile(
        leading: const Icon(Icons.restore, color: Colors.red),
        title: Text(
          TranslationService.translate(context, 'backup_restore_title'),
        ),
        subtitle: Text(
          TranslationService.translate(context, 'backup_restore_subtitle'),
        ),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HelpAffordance(topicId: 'backup_restore_json'),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => BackupActions.restoreCatalogJson(context),
      ),
      // Carte conditionnelle: rollback de la dernière restauration.
      const _RollbackTile(),
    ];
  }

  /// The local-network (Wi-Fi/mDNS) toggle card. Self-contained (wraps its own
  /// [Consumer]) so it renders both inside the Network accordion and inside the
  /// springboard "Partager sur mon réseau Wi-Fi" bottom sheet.
  Widget _buildLocalNetworkCard(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        String t(String key) => TranslationService.translate(context, key);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.wifi),
                title: Text(t('settings_network_discovery')),
                subtitle: Text(t('settings_network_discovery_desc')),
                value: themeProvider.networkEnabled,
                onChanged: (value) => themeProvider.setNetworkEnabled(value),
              ),
              if (themeProvider.networkEnabled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.devices),
                  title: Text(t('settings_network_peers_detected')),
                  trailing: Text(
                    '${MdnsService.peers.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(t('settings_reshow_invite_banner')),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('invite_banner_dismissed');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t('settings_reshow_invite_banner_done')),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSharingModesCard(
    BuildContext context,
    String Function(String) t,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('settings_sharing_modes_title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildModeRow(
              context,
              Icons.link,
              t('settings_mode_invite_title'),
              t('settings_mode_invite_desc'),
            ),
            const SizedBox(height: 10),
            _buildModeRow(
              context,
              Icons.wifi,
              t('settings_mode_wifi_title'),
              t('settings_mode_wifi_desc'),
            ),
            const SizedBox(height: 10),
            _buildModeRow(
              context,
              Icons.public,
              t('settings_mode_directory_title'),
              t('settings_mode_directory_desc'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeRow(
    BuildContext context,
    IconData icon,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall,
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' - $desc'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Auto-connect relay when remote reachable is enabled.
  Future<void> _autoConnectRelay() async {
    if (_relayConnected) return;
    final api = Provider.of<ApiService>(context, listen: false);
    final url = kReleaseMode
        ? ApiService.hubUrl
        : (_relayUrlController.text.trim().isNotEmpty
              ? _relayUrlController.text.trim()
              : ApiService.hubUrl);
    try {
      final res = await api.setupRelay(relayUrl: url);
      if (!mounted) return;
      if (res.statusCode == 200 && res.data is Map) {
        setState(() {
          _relayConnected = true;
          _relayMailboxUuid = res.data['mailbox_uuid'] as String?;
          _relayUrlController.text = url;
        });
        // Publish new relay credentials to hub so peers can reach this mailbox.
        if (mounted) {
          await context.read<HubDirectoryProvider>().ensureRelayPublished();
        }
      }
    } catch (e) {
      debugPrint('Auto-connect relay failed: $e');
    }
  }

  /// Relay technical details shown inside the accordion.
  Widget _buildRelayDetails(BuildContext context) {
    final api = Provider.of<ApiService>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: _relayConnected ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                _relayConnected
                    ? (TranslationService.translate(
                            context,
                            'relay_connected',
                          ) ??
                          'Connected')
                    : (TranslationService.translate(
                            context,
                            'relay_disconnected',
                          ) ??
                          'Not connected'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Hub URL is only editable in debug builds to prevent
          // token/cache invalidation cascades when switching hubs.
          if (!kReleaseMode)
            TextField(
              controller: _relayUrlController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'relay_url_label') ??
                    'Hub URL',
                hintText: ApiService.hubUrl,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              enabled: !_relayLoading,
            ),
          if (_relayMailboxUuid != null) ...[
            const SizedBox(height: 6),
            Text(
              'Mailbox: ${_relayMailboxUuid!.substring(0, 8)}...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _relayConnected
                ? OutlinedButton.icon(
                    onPressed: _relayLoading
                        ? null
                        : () async {
                            final confirmed = await _confirmDestructiveAction(
                              context,
                              titleKey: 'confirm_remote_disconnect_title',
                              titleFallback: 'Disconnect remote server?',
                              bodyKey: 'confirm_remote_disconnect_body',
                              bodyFallback:
                                  'Your invited contacts will no longer reach you outside your local network.',
                              actionKey: 'confirm_remote_disconnect_action',
                              actionFallback: 'Disconnect',
                            );
                            if (!confirmed) return;
                            setState(() => _relayLoading = true);
                            try {
                              await api.disconnectRelay();
                              if (!mounted) return;
                              setState(() {
                                _relayConnected = false;
                                _relayMailboxUuid = null;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _relayLoading = false);
                              }
                            }
                          },
                    icon: _relayLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_off),
                    label: Text(
                      TranslationService.translate(
                            context,
                            'relay_disconnect',
                          ) ??
                          'Disconnect',
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _relayLoading
                        ? null
                        : () async {
                            final url = kReleaseMode
                                ? ApiService.hubUrl
                                : _relayUrlController.text.trim();
                            if (url.isEmpty) return;

                            setState(() => _relayLoading = true);
                            try {
                              final res = await api.setupRelay(relayUrl: url);
                              if (!mounted) return;
                              if (res.statusCode == 200 && res.data is Map) {
                                setState(() {
                                  _relayConnected = true;
                                  _relayMailboxUuid =
                                      res.data['mailbox_uuid'] as String?;
                                });
                                // Publish new relay credentials to hub
                                // so peers can reach this mailbox.
                                if (context.mounted) {
                                  await context
                                      .read<HubDirectoryProvider>()
                                      .ensureRelayPublished();
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      TranslationService.translate(
                                            context,
                                            'relay_connected',
                                          ) ??
                                          'Connected',
                                    ),
                                  ),
                                );
                              } else {
                                final error =
                                    res.data?['error'] ?? 'Connection failed';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _relayLoading = false);
                              }
                            }
                          },
                    icon: _relayLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      TranslationService.translate(context, 'relay_connect') ??
                          'Connect',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public Directory section
  // ---------------------------------------------------------------------------

  Widget _buildDirectorySection(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, dirProvider, _) {
        final config = dirProvider.config;
        final isListed = config?.isListed ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(
                      context,
                      'directory_settings_title',
                    ) ??
                    'Public Directory',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  // Top-level toggle: enable the hub online features.
                  // Browsing the directory is always available (ADR-015 public
                  // endpoint); this toggle gates the bidirectional features:
                  // X25519 key publishing, real-time nudges, and access to
                  // the sub-toggles (isListed, contact, website).
                  SwitchListTile(
                    secondary: const Icon(Icons.explore),
                    title: Text(
                      TranslationService.translate(
                            context,
                            'hub_coming_soon_toggle',
                          ) ??
                          'Public directory',
                    ),
                    subtitle: Text(
                      TranslationService.translate(
                            context,
                            'hub_coming_soon_desc',
                          ) ??
                          'Browse and follow other public libraries',
                    ),
                    value: dirProvider.isHubEnabled,
                    onChanged: (value) async {
                      await dirProvider.setHubEnabled(value);
                      if (value) {
                        dirProvider.initAndSyncCatalog();
                      }
                    },
                  ),

                  if (dirProvider.isHubEnabled) ...[
                    const Divider(height: 1),
                    // Sub-toggle: opt-in to be listed (so others can find you)
                    SwitchListTile(
                      secondary: const Icon(Icons.public),
                      title: Text(
                        TranslationService.translate(
                              context,
                              'directory_listed_title',
                            ) ??
                            'Appear in the public directory',
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                              context,
                              'directory_listed_desc',
                            ) ??
                            'Other libraries can discover and follow you',
                      ),
                      value: isListed,
                      onChanged: dirProvider.configLoading
                          ? null
                          : (value) => _toggleDirectoryListing(
                              context,
                              dirProvider,
                              value,
                            ),
                    ),

                    if (isListed) ...[
                      const Divider(height: 1),
                      // Advanced settings accordion
                      ExpansionTile(
                        leading: const Icon(Icons.tune),
                        title: Text(
                          TranslationService.translate(
                                context,
                                'directory_advanced_settings',
                              ) ??
                              'Advanced settings',
                        ),
                        children: [
                          // Requires approval toggle: new followers need manual
                          // approval before reading the catalog. Hub honors this
                          // in DirectoryService::follow() (pending vs active).
                          SwitchListTile(
                            secondary: const Icon(Icons.how_to_reg),
                            title: Text(
                              TranslationService.translate(
                                    context,
                                    'directory_requires_approval_title',
                                  ) ??
                                  'Require approval for followers',
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                    context,
                                    'directory_requires_approval_desc',
                                  ) ??
                                  'New followers need your approval before accessing your catalog',
                            ),
                            value: config?.requiresApproval ?? false,
                            onChanged: dirProvider.configLoading
                                ? null
                                : (value) => _updateDirectoryConfig(
                                    context,
                                    dirProvider,
                                    requiresApproval: value,
                                  ),
                          ),
                          // Allow borrowing toggle: hub-mediated loan requests.
                          // Enforced server-side in DirectoryService::createBorrowRequest().
                          SwitchListTile(
                            secondary: const Icon(Icons.menu_book_outlined),
                            title: Text(
                              TranslationService.translate(
                                    context,
                                    'hub_allow_borrowing',
                                  ) ??
                                  'Allow borrowing requests',
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                    context,
                                    'hub_allow_borrowing_desc',
                                  ) ??
                                  'Let your followers request to borrow your books via the hub',
                            ),
                            value: config?.allowBorrowing ?? false,
                            onChanged: dirProvider.configLoading
                                ? null
                                : (value) => _updateDirectoryConfig(
                                    context,
                                    dirProvider,
                                    allowBorrowing: value,
                                  ),
                          ),
                          // accept_from selector removed (non-functional)
                        ],
                      ),
                      // Contact info (mandatory for listed libraries)
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          controller: _hubContactController,
                          decoration: InputDecoration(
                            labelText:
                                TranslationService.translate(
                                  context,
                                  'hub_contact_label',
                                ) ??
                                'Contact info (visible to approved followers)',
                            hintText:
                                TranslationService.translate(
                                  context,
                                  'hub_contact_hint',
                                ) ??
                                'Email, phone, address...',
                            prefixIcon: const Icon(Icons.contact_mail),
                            border: const OutlineInputBorder(),
                            helperText:
                                TranslationService.translate(
                                  context,
                                  'hub_contact_encrypted_notice',
                                ) ??
                                'Encrypted - only visible to your approved followers',
                            helperMaxLines: 2,
                          ),
                          // Start at one line (so a single-line email isn't
                          // glued to the top of a fixed 2-line box) and grow to
                          // two lines for longer entries like phone + address.
                          // textAlignVertical is ignored when maxLines > 1, so
                          // minLines is the correct lever here.
                          minLines: 1,
                          maxLines: 2,
                          onChanged: (value) =>
                              dirProvider.setContactInfo(value),
                        ),
                      ),
                      // Website (optional, public)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: TextField(
                          controller: _hubWebsiteController,
                          decoration: InputDecoration(
                            labelText:
                                TranslationService.translate(
                                  context,
                                  'hub_website_label',
                                ) ??
                                'Website (optional)',
                            hintText: 'https://...',
                            prefixIcon: const Icon(Icons.language),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          onChanged: (value) => dirProvider.setWebsite(value),
                        ),
                      ),
                    ],
                  ], // if (dirProvider.isHubEnabled)
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // _buildAcceptFromSelector removed (dead code: hub ignores these values)

  Future<void> _toggleDirectoryListing(
    BuildContext context,
    HubDirectoryProvider dirProvider,
    bool newValue,
  ) async {
    if (!newValue) {
      final confirmed = await _confirmDestructiveAction(
        context,
        titleKey: 'confirm_directory_unlist_title',
        titleFallback: 'Leave the public directory?',
        bodyKey: 'confirm_directory_unlist_body',
        bodyFallback:
            'Other libraries will no longer be able to discover you. Existing followers stay active.',
        actionKey: 'confirm_directory_unlist_action',
        actionFallback: 'Leave directory',
      );
      if (!confirmed) return;
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final libraryName = themeProvider.libraryName;

    final config = dirProvider.config;
    // Use existing node_id, or fall back to the stable library UUID (first registration).
    final nodeId = config?.nodeId ?? await authService.getOrCreateLibraryUuid();

    final ffi = FfiService();
    final bookCount = await ffi.countBooks();

    // Fetch local x25519 public key for E2EE contact sharing
    String? x25519PublicKey;
    try {
      x25519PublicKey = await ffi.getLocalX25519PublicKey();
    } catch (_) {}

    final website = dirProvider.websiteUrl.isNotEmpty
        ? dirProvider.websiteUrl
        : null;

    final ok = await dirProvider.register(
      nodeId: nodeId,
      displayName: libraryName,
      bookCount: bookCount,
      isListed: newValue,
      requiresApproval: config?.requiresApproval ?? false,
      acceptFrom: config?.acceptFrom ?? 'everyone',
      allowBorrowing: config?.allowBorrowing ?? true,
      locationCountry: themeProvider.country,
      x25519PublicKey: x25519PublicKey,
      website: website,
    );

    if (ok && newValue) {
      // Push the full ISBN catalog to the hub after listing.
      await dirProvider.syncCatalog();

      // Auto-enable caching when activating hub sharing
      if (!themeProvider.peerOfflineCachingEnabled) {
        themeProvider.setPeerOfflineCachingEnabled(true);
      }
      if (!themeProvider.allowLibraryCaching) {
        themeProvider.setAllowLibraryCaching(true);
      }
    }

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dirProvider.configError ??
                (TranslationService.translate(context, 'error_network') ??
                    'Network error'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmDestructiveAction(
    BuildContext context, {
    required String titleKey,
    required String titleFallback,
    required String bodyKey,
    required String bodyFallback,
    required String actionKey,
    required String actionFallback,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            TranslationService.translate(dialogContext, titleKey) ??
                titleFallback,
          ),
          content: Text(
            TranslationService.translate(dialogContext, bodyKey) ??
                bodyFallback,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                TranslationService.translate(dialogContext, 'cancel') ??
                    'Cancel',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                TranslationService.translate(dialogContext, actionKey) ??
                    actionFallback,
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _updateDirectoryConfig(
    BuildContext context,
    HubDirectoryProvider dirProvider, {
    bool? requiresApproval,
    String? acceptFrom,
    bool? allowBorrowing,
  }) async {
    final config = dirProvider.config;
    if (config == null) return;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final libraryName = themeProvider.libraryName;

    final ffi = FfiService();
    final bookCount = await ffi.countBooks();

    String? x25519PublicKey;
    try {
      x25519PublicKey = await ffi.getLocalX25519PublicKey();
    } catch (_) {}

    final website = dirProvider.websiteUrl.isNotEmpty
        ? dirProvider.websiteUrl
        : null;

    final ok = await dirProvider.register(
      nodeId: config.nodeId,
      displayName: libraryName,
      bookCount: bookCount,
      isListed: config.isListed,
      requiresApproval: requiresApproval ?? config.requiresApproval,
      acceptFrom: acceptFrom ?? config.acceptFrom,
      allowBorrowing: allowBorrowing ?? config.allowBorrowing,
      locationCountry: themeProvider.country,
      x25519PublicKey: x25519PublicKey,
      website: website,
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dirProvider.configError ??
                (TranslationService.translate(context, 'error_network') ??
                    'Network error'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildMcpModuleToggle() {
    if (!_matchesSearch(['mcp_integration', 'mcp_description'])) {
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

  /// Opt-in city sharing block (ADR-035 Phase 1). Renders the second toggle
  /// "Partager ma ville" and, when ON, the picker that resolves a GeoNames
  /// id from the user's country file.
  Widget _buildCitySection(BuildContext context, ThemeProvider themeProvider) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, hub, _) {
        final cs = Theme.of(context).colorScheme;
        // Sharing a city only makes sense if the library is listed in the
        // public directory (otherwise there is no public profile to attach it
        // to). Gate the toggle on that, and explain why when it is off.
        final canShareCity = hub.isListed;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                TranslationService.translate(context, 'settings_share_city') ??
                    'Share my city',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                canShareCity
                    ? (TranslationService.translate(
                            context,
                            'settings_share_city_desc',
                          ) ??
                          'Adds your city to your public profile so nearby readers can find you. Off by default.')
                    : TranslationService.translate(
                        context,
                        'settings_share_city_requires_directory',
                      ),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              value: hub.isShareCityEnabled && canShareCity,
              activeColor: cs.primary,
              onChanged: canShareCity
                  ? (value) async {
                      await hub.setShareCity(value);
                      if (!value) {
                        // User opted out: drop the local pick and clear the hub
                        // so the public profile no longer carries a city.
                        await hub.setLocalCityId(null);
                        try {
                          await hub.syncLocationCityId(null);
                        } catch (e) {
                          debugPrint('Hub locationCityId clear failed: $e');
                        }
                      }
                    }
                  : null,
            ),
            if (canShareCity && hub.isShareCityEnabled) ...[
              const SizedBox(height: 8),
              _buildCityPicker(context, themeProvider, hub),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCityPicker(
    BuildContext context,
    ThemeProvider themeProvider,
    HubDirectoryProvider hub,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    final country = themeProvider.country;
    final pickedId = hub.localCityId;

    return Material(
      color: Colors.transparent,
      // Semantics(button: true, label: ...) makes the picker discoverable
      // to screen readers; the inner Text still carries the current
      // selection so the announcement reads e.g. "Open city picker, Paris,
      // button" (ADR-035, RGAA A1).
      child: Semantics(
        button: true,
        label:
            TranslationService.translate(
              context,
              'settings_open_city_picker_a11y',
            ) ??
            'Open city picker',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openCityPicker(context, country, hub),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_city_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: pickedId == null
                      ? Text(
                          TranslationService.translate(
                                context,
                                'settings_city_pick',
                              ) ??
                              'Pick a city',
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : FutureBuilder<CityRecord?>(
                          future: CityRepository.shared().lookupById(
                            pickedId,
                            country: country,
                          ),
                          builder: (context, snapshot) {
                            final label =
                                snapshot.data?.name ??
                                (TranslationService.translate(
                                      context,
                                      'settings_city_unknown',
                                    ) ??
                                    'Unknown city');
                            final subtitle = snapshot.data?.subtitle;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: primary.withValues(alpha: 0.75),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
                Icon(Icons.arrow_drop_down, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCityPicker(
    BuildContext context,
    String country,
    HubDirectoryProvider hub,
  ) async {
    final picked = await showModalBottomSheet<CityRecord>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => CityPickerSheet(country: country),
    );
    if (picked == null) return;
    // The picked CityRecord knows its country - thread it through both
    // calls so the hub upsert always carries the (city, country) pair.
    // Without this, the city was pushed alone and the hub-stored country
    // could stay NULL, silently excluding this profile from the
    // country+city directory filter (asymmetry observed iPhone-vs-Mac).
    await hub.setLocalCityId(picked.id, country: picked.country);
    try {
      await hub.syncLocationCityId(picked.id, country: picked.country);
    } catch (e) {
      debugPrint('Hub locationCityId update failed: $e');
    }
  }

  Widget _buildCountryPicker(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final countryCode = themeProvider.country;
    Country? current;
    try {
      current = CountryParser.parseCountryCode(countryCode);
    } catch (_) {
      // Unknown code, will show just the code
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showCountryPicker(
            context: context,
            showPhoneCode: false,
            favorite: ['FR', 'BE', 'CH', 'CA'],
            countryListTheme: CountryListThemeData(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              inputDecoration: InputDecoration(
                hintText:
                    TranslationService.translate(context, 'search') ?? 'Search',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            onSelect: (Country selected) async {
              await themeProvider.setCountry(selected.countryCode);
              if (!context.mounted) return;
              try {
                await context.read<HubDirectoryProvider>().syncLocationCountry(
                  selected.countryCode,
                );
              } catch (e) {
                debugPrint('Hub locationCountry update failed: $e');
              }
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(
                current?.flagEmoji ?? '',
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  current?.name ?? countryCode,
                  style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.arrow_drop_down, color: primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(
    BuildContext context,
    String presetName,
    String label,
    IconData icon,
    Color color,
    ThemeProvider themeProvider,
  ) {
    return Material(
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
    );
  }

  Widget _buildNavStyleSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomNav = themeProvider.bottomNavEnabled;

    Widget navOption({
      required bool selected,
      required IconData icon,
      required String labelKey,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : isDark
                  ? theme.colorScheme.surface.withValues(alpha: 0.8)
                  : Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey.withValues(alpha: 0.3),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(context, labelKey),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'nav_style_label'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          TranslationService.translate(context, 'nav_style_desc'),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.grey[500],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            navOption(
              selected: !bottomNav,
              icon: Icons.menu,
              labelKey: 'nav_style_side_menu',
              onTap: () => themeProvider.setBottomNavEnabled(false),
            ),
            const SizedBox(width: 12),
            navOption(
              selected: bottomNav,
              icon: Icons.dock,
              labelKey: 'nav_style_bottom_bar',
              onTap: () => themeProvider.setBottomNavEnabled(true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    ThemeRegistry.initialize();
    final themes = ThemeRegistry.all;
    final currentId = themeProvider.themeStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: themes.map((theme) {
            final isSelected = theme.id == currentId;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: theme.id != themes.last.id ? 8.0 : 0,
                ),
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await themeProvider.setThemeStyle(theme.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.previewColor.withValues(alpha: 0.15)
                          : Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.previewColor
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.previewSecondaryColor,
                                theme.previewColor,
                              ],
                              stops: const [0.5, 0.5],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _themeDisplayName(context, theme.id),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? theme.previewColor
                                : Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTextScaleSlider(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    const steps = [0.85, 1.0, 1.15, 1.3, 1.4];
    final current = themeProvider.textScaleFactor;
    // Find closest step index
    int stepIndex = 0;
    double minDist = (steps[0] - current).abs();
    for (int i = 1; i < steps.length; i++) {
      final dist = (steps[i] - current).abs();
      if (dist < minDist) {
        minDist = dist;
        stepIndex = i;
      }
    }

    String stepLabel(int index) {
      switch (index) {
        case 0:
          return TranslationService.translate(context, 'text_size_small') ??
              'Small';
        case 1:
          return TranslationService.translate(context, 'text_size_default') ??
              'Default';
        default:
          return TranslationService.translate(context, 'text_size_large') ??
              'Large';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'text_size') ?? 'Text Size',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              // Preview text
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 24 * steps[stepIndex],
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stepLabel(stepIndex),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 8),
              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: stepIndex.toDouble(),
                  min: 0,
                  max: (steps.length - 1).toDouble(),
                  divisions: steps.length - 1,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (value) {
                    HapticFeedback.lightImpact();
                    themeProvider.setTextScaleFactor(steps[value.round()]);
                  },
                ),
              ),
              // Min/max labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'A',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    Text(
                      'A',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // All available reading languages with native names (shared constant)
  static const Map<String, String> _availableLanguages = kLanguageNativeNames;

  /// Reading-language subtitle + selectable chips. Self-contained (wraps its
  /// own [Consumer]) so it renders in the Languages accordion and in the
  /// springboard "Add a reading language" bottom sheet.
  Widget _buildReadingLanguagesField(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final userLangs = themeProvider.userLanguages;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TranslationService.translate(context, 'languages_reading') ??
                  'My reading languages',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              TranslationService.translate(context, 'languages_reading_desc') ??
                  'Select the languages you read in',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableLanguages.entries.map((entry) {
                final code = entry.key;
                final name = entry.value;
                final isSelected = userLangs.contains(code);
                return FilterChip(
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newLangs = List<String>.from(userLangs);
                    if (selected) {
                      newLangs.add(code);
                    } else {
                      if (newLangs.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              TranslationService.translate(
                                    context,
                                    'languages_min_one',
                                  ) ??
                                  'At least one language required',
                            ),
                          ),
                        );
                        return;
                      }
                      newLangs.remove(code);
                    }
                    themeProvider.setUserLanguages(newLangs);
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    // Normalize locale tag to match dropdown items (e.g. fr-FR -> fr)
    final rawLocale = themeProvider.localeTag;
    final currentLocale = ThemeProvider.supportedUILanguages.contains(rawLocale)
        ? rawLocale
        : ThemeProvider.supportedUILanguages.contains(
            rawLocale.split('-').first,
          )
        ? rawLocale.split('-').first
        : 'en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reading languages (extracted so the springboard "Add a reading
        // language" sheet can show the same chips).
        _buildReadingLanguagesField(context),

        const SizedBox(height: 24),

        // UI language dropdown
        Text(
          TranslationService.translate(context, 'languages_ui') ??
              'Interface language',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          TranslationService.translate(context, 'languages_ui_desc') ??
              'The app will be displayed in this language',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: DropdownButton<String>(
            value: currentLocale,
            isExpanded: true,
            underline: const SizedBox(),
            items: ThemeProvider.supportedUILanguages
                .map(
                  (code) => DropdownMenuItem<String>(
                    value: code,
                    child: Text(_availableLanguages[code] ?? code),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                themeProvider.setLocale(parseLocaleTag(value));
              }
            },
          ),
        ),

        const SizedBox(height: 24),

        // Country
        Text(
          TranslationService.translate(context, 'settings_country') ??
              'Country',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildCountryPicker(context, themeProvider),

        const SizedBox(height: 24),

        // City sharing (ADR-035 §3): opt-in toggle + city picker, both live
        // here so the location preferences cluster in one place.
        _buildCitySection(context, themeProvider),
      ],
    );
  }

  String _themeDisplayName(BuildContext context, String themeId) {
    final key = 'theme_$themeId';
    return TranslationService.translate(context, key) ??
        ThemeRegistry.get(themeId)?.displayName ??
        themeId;
  }

  // _buildRelayHubCard removed - relay details now inline in _buildRelayDetails

  Widget _buildLoanDurationSection(BuildContext context) {
    if (!_matchesSearch([
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
    if (!_matchesSearch([titleKey, descKey])) return const SizedBox.shrink();
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

  Widget _buildSearchConfiguration(BuildContext context) {
    final deviceLang = Localizations.localeOf(context).languageCode;
    final bnfDefault = deviceLang == 'fr';
    final googleDefault = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Column(
            children: [
              _buildSwitchTile(
                context,
                'Inventaire.io',
                'source_inventaire_desc',
                _searchPrefs['inventaire'] ?? true,
                (val) => _updateSearchPreference('inventaire', val),
                icon: Icons.language,
              ),
              _buildSwitchTile(
                context,
                'Bibliothèque Nationale (BNF)',
                'source_bnf_desc',
                _searchPrefs['bnf'] ?? bnfDefault,
                (val) => _updateSearchPreference('bnf', val),
                icon: Icons.account_balance,
              ),
              _buildSwitchTile(
                context,
                'OpenLibrary',
                'source_openlibrary_desc',
                _searchPrefs['openlibrary'] ?? true,
                (val) => _updateSearchPreference('openlibrary', val),
                icon: Icons.local_library,
              ),
              _buildSwitchTile(
                context,
                'Google Books',
                'source_google_desc',
                _searchPrefs['google_books'] ?? googleDefault,
                (val) => _updateSearchPreference('google_books', val),
                icon: Icons.search,
                tag: TranslationService.translate(
                  context,
                  'google_books_advanced_tag',
                ),
              ),
              if ((_searchPrefs['google_books'] ?? googleDefault) &&
                  _googleBooksApiKey.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'google_books_no_api_key_warning',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_searchPrefs['google_books'] ?? googleDefault)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Plain toggle button instead of a nested ExpansionTile:
                      // a TextField inside nested ExpansionTiles crashes layout
                      // during the expand animation (intrinsic measurement of a
                      // TextField -> unbounded constraints). This keeps the same
                      // collapse/reveal behaviour without the nesting.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            _showGoogleAdvanced
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          label: Text(
                            TranslationService.translate(
                              context,
                              'google_books_advanced_options',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _showGoogleAdvanced = !_showGoogleAdvanced,
                          ),
                        ),
                      ),
                      if (_showGoogleAdvanced) ...[
                        const SizedBox(height: 4),
                        TextField(
                          controller: _apiKeyController,
                          decoration: InputDecoration(
                            labelText:
                                TranslationService.translate(
                                  context,
                                  'google_api_key_label',
                                ) ??
                                'Google Books API Key',
                            hintText: 'AIzaSy...',
                            helperText:
                                TranslationService.translate(
                                  context,
                                  'google_api_key_helper',
                                ) ??
                                'Get a free key at console.cloud.google.com',
                            helperMaxLines: 2,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.save),
                              tooltip: TranslationService.translate(
                                context,
                                'save',
                              ),
                              onPressed: _saveGoogleBooksApiKey,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          obscureText: true,
                          onSubmitted: (_) => _saveGoogleBooksApiKey(),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://support.google.com/googleapi/answer/6158862',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  TranslationService.translate(
                                    context,
                                    'google_books_api_key_help_link',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitleKey,
    bool value,
    ValueChanged<bool> onChanged, {
    IconData? icon,
    String? tag,
  }) {
    return SwitchListTile(
      secondary: icon != null ? Icon(icon) : null,
      title: Row(
        children: [
          Flexible(child: Text(title)),
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
        ],
      ),
      subtitle: Text(
        TranslationService.translate(context, subtitleKey) ?? subtitleKey,
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _saveGoogleBooksApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key == _googleBooksApiKey) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateProfile(
        data: {
          'api_keys': {'google_books': key},
        },
      );

      setState(() => _googleBooksApiKey = key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'api_key_saved') ??
                  'API key saved',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_update')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateSearchPreference(String source, bool enabled) async {
    setState(() {
      _searchPrefs[source] = enabled;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);

      // Use updateProfile which properly syncs to enabled_modules in database.
      // This ensures Google Books and other module toggles persist correctly.
      await api.updateProfile(data: {'fallback_preferences': _searchPrefs});

      if (_userStatus != null) {
        if (_userStatus!['config'] == null) {
          _userStatus!['config'] = {};
        }
        _userStatus!['config']['fallback_preferences'] = _searchPrefs;
      }
    } catch (e) {
      debugPrint('Error updating search preference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_update')}: $e',
            ),
          ),
        );
      }
    }
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

  Future<void> _setupMfa() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final response = await apiService.setup2Fa();
      final data = response.data;
      final secret = data['secret'];
      final qrCode = data['qr_code'];

      if (!mounted) return;

      final codeController = TextEditingController();
      String? verifyError;

      await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              TranslationService.translate(context, 'setup_2fa') ?? 'Setup 2FA',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TranslationService.translate(context, 'scan_qr_code') ??
                        'Scan this QR code with your authenticator app:',
                  ),
                  const SizedBox(height: 16),
                  if (qrCode != null)
                    Image.memory(base64Decode(qrCode), height: 200, width: 200),
                  const SizedBox(height: 16),
                  SelectableText(
                    '${TranslationService.translate(context, 'secret_key') ?? 'Secret Key'}: $secret',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'verification_code',
                          ) ??
                          'Verification Code',
                      errorText: verifyError,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  TranslationService.translate(context, 'cancel') ?? 'Cancel',
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => verifyError = null);
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'invalid_code',
                          ) ??
                          'Invalid code',
                    );
                    return;
                  }

                  try {
                    await apiService.verify2Fa(secret, code);
                    if (mounted) {
                      Navigator.pop(context);
                      _fetchSettings();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'mfa_enabled_success',
                                ) ??
                                'MFA Enabled Successfully',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'verification_failed',
                          ) ??
                          'Verification failed',
                    );
                  }
                },
                child: Text(
                  TranslationService.translate(context, 'verify') ?? 'Verify',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_initializing_mfa') ?? 'Error initializing MFA'}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final hasPassword = await authService.hasPasswordSet();

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? errorText;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            hasPassword
                ? (TranslationService.translate(context, 'change_password') ??
                      'Change Password')
                : (TranslationService.translate(context, 'set_password') ??
                      'Set Password'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasPassword)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      TranslationService.translate(
                            context,
                            'first_time_password',
                          ) ??
                          'Set a password to protect your data',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                if (hasPassword)
                  TextField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'current_password',
                          ) ??
                          'Current Password',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (hasPassword) const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(context, 'new_password') ??
                        'New Password',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(
                          context,
                          'confirm_password',
                        ) ??
                        'Confirm Password',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (hasPassword)
              TextButton(
                onPressed: () async {
                  // Ask for current password first
                  if (currentPasswordController.text.isEmpty) {
                    setState(
                      () => errorText =
                          TranslationService.translate(
                            context,
                            'password_required',
                          ) ??
                          'Password is required',
                    );
                    return;
                  }
                  final isValid = await authService.verifyPassword(
                    currentPasswordController.text,
                  );
                  if (!isValid) {
                    setState(
                      () => errorText =
                          TranslationService.translate(
                            context,
                            'password_incorrect',
                          ) ??
                          'Incorrect password',
                    );
                    return;
                  }
                  // Confirm removal
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        TranslationService.translate(ctx, 'remove_password') ??
                            'Remove password',
                      ),
                      content: Text(
                        TranslationService.translate(
                              ctx,
                              'remove_password_confirm',
                            ) ??
                            'Are you sure?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            TranslationService.translate(ctx, 'cancel') ??
                                'Cancel',
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            TranslationService.translate(
                                  ctx,
                                  'remove_password',
                                ) ??
                                'Remove password',
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await authService.removePassword(
                      currentPasswordController.text,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'password_removed_success',
                                ) ??
                                'Password removed successfully',
                          ),
                        ),
                      );
                    }
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(
                  TranslationService.translate(context, 'remove_password') ??
                      'Remove password',
                ),
              ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newPasswordController.text.length < 4) {
                  setState(
                    () => errorText =
                        TranslationService.translate(
                          context,
                          'password_too_short',
                        ) ??
                        'Password must be at least 4 characters',
                  );
                  return;
                }
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  setState(
                    () => errorText =
                        TranslationService.translate(
                          context,
                          'passwords_dont_match',
                        ) ??
                        'Passwords do not match',
                  );
                  return;
                }

                if (hasPassword) {
                  final isValid = await authService.verifyPassword(
                    currentPasswordController.text,
                  );
                  if (!isValid) {
                    setState(
                      () => errorText =
                          TranslationService.translate(
                            context,
                            'password_incorrect',
                          ) ??
                          'Incorrect password',
                    );
                    return;
                  }
                  await authService.changePassword(
                    currentPasswordController.text,
                    newPasswordController.text,
                  );
                } else {
                  await authService.savePassword(newPasswordController.text);
                }

                // Invalidate session so next launch requires the new password
                await authService.saveToken(
                  'local-auto-token-${DateTime.now().millisecondsSinceEpoch}',
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(
                              context,
                              'password_changed_success',
                            ) ??
                            'Password changed successfully',
                      ),
                    ),
                  );
                }
              },
              child: Text(
                TranslationService.translate(context, 'save') ?? 'Save',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conditional "Restaurer la version précédente" tile (ADR-037 §5).
///
/// Polls `list_available_rollbacks_ffi` once at mount and renders nothing
/// when the list is empty. Each rollback is kept on disk for 24h after a
/// Replace restore; the `run_startup_maintenance` purge sweeps expired
/// entries on the next app launch.
class _RollbackTile extends StatefulWidget {
  const _RollbackTile();

  @override
  State<_RollbackTile> createState() => _RollbackTileState();
}

class _RollbackTileState extends State<_RollbackTile> {
  rust.FrbRollbackInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<String> _liveDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/bibliogenius.db';
  }

  Future<void> _refresh() async {
    try {
      final dbPath = await _liveDbPath();
      final list = await rust.listAvailableRollbacksFfi(dbPath: dbPath);
      if (!mounted) return;
      setState(() {
        _info = list.isEmpty ? null : list.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final info = _info;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(
          ctx,
          'backup_rollback_dialog_title',
        )),
        content: Text(TranslationService.translate(
          ctx,
          'backup_rollback_dialog_message',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(
              ctx,
              'wizard_restore_button_cancel',
            )),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(TranslationService.translate(
              ctx,
              'backup_rollback_dialog_confirm',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dbPath = await _liveDbPath();
      await rust.restoreFromRollbackFfi(
        rollbackPath: info.path,
        dbPath: dbPath,
      );
      if (!mounted) return;
      io.exit(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(TranslationService.translate(
            context,
            'backup_rollback_error',
            params: {'error': '$e'},
          )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final ageHours = (info.ageSeconds / 3600).floor();
    final remainingHours = 24 - ageHours;
    return ListTile(
      leading: const Icon(Icons.history, color: Colors.orange),
      title: Text(TranslationService.translate(
        context,
        'backup_rollback_title',
      )),
      subtitle: Text(TranslationService.translate(
        context,
        'backup_rollback_subtitle',
        params: {
          'age_hours': '$ageHours',
          'remaining_hours': '$remainingHours',
        },
      )),
      trailing: const Icon(Icons.chevron_right),
      onTap: _confirm,
    );
  }
}
