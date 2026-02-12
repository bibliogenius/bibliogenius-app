import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../widgets/genie_app_bar.dart';
import '../widgets/contextual_help_sheet.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_design.dart';
import '../themes/base/theme_registry.dart';
import '../utils/app_constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _userStatus;
  Map<String, bool> _searchPrefs = {};

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    setState(() => _isLoading = true);

    try {
      // Fetch Config
      final configRes = await api.getLibraryConfig();
      if (configRes.statusCode == 200) {
        _config = configRes.data;
        final name = _config?['library_name'] ?? _config?['name'];
        if (name != null) {
          themeProvider.setLibraryName(name);
        }
        final profileType = _config?['profile_type'];
        if (profileType != null) {
          themeProvider.setProfileType(profileType);
        }
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
        }
      }

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
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'nav_settings'),
        leading: isWide
            ? null
            : IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
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
            // App Settings Section
            Text(
              TranslationService.translate(context, 'app_settings'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Theme Selection
            _buildThemeSelector(context, themeProvider),
            const SizedBox(height: 24),

            // Text Size
            _buildTextScaleSlider(context, themeProvider),
            const SizedBox(height: 24),

            // Quick Presets Section
            Text(
              TranslationService.translate(context, 'quick_presets') ??
                  'Quick Presets',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                    TranslationService.translate(context, 'preset_librarian') ??
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
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Modules Section
            Text(
              TranslationService.translate(context, 'modules') ?? 'Modules',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                // Simplified Mode toggle (replaces kid profile)
                _buildModuleToggle(
                  context,
                  'simplified_mode',
                  'simplified_mode_desc',
                  Icons.child_care,
                  themeProvider.simplifiedMode,
                  (value) => themeProvider.setSimplifiedMode(value),
                ),
                _buildModuleToggle(
                  context,
                  'quotes_module',
                  'quotes_module_desc',
                  Icons.format_quote,
                  themeProvider.quotesEnabled,
                  (value) => themeProvider.setQuotesEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'gamification_module',
                  'gamification_desc',
                  Icons.emoji_events,
                  themeProvider.gamificationEnabled,
                  (value) => themeProvider.setGamificationEnabled(value),
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
                      (value) =>
                          themeProvider.setNetworkGamificationEnabled(value),
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
                    ),
                  ),
                _buildModuleToggle(
                  context,
                  'collections_module',
                  'collections_module_desc',
                  Icons.collections_bookmark,
                  themeProvider.collectionsEnabled,
                  (value) => themeProvider.setCollectionsEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'commerce_module',
                  'commerce_module_desc',
                  Icons.storefront,
                  themeProvider.commerceEnabled,
                  (value) => themeProvider.setCommerceEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'audio_module',
                  'audio_module_desc',
                  Icons.headphones,
                  themeProvider.audioEnabled,
                  (value) => themeProvider.setAudioEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'network_module',
                  'network_module_desc',
                  Icons.hub,
                  themeProvider.networkEnabled,
                  (value) => themeProvider.setNetworkEnabled(value),
                  tag: TranslationService.translate(
                    context,
                    'tag_experimental',
                  ),
                ),
                // Sub-option for network module: peer offline caching
                if (themeProvider.networkEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: _buildModuleToggle(
                      context,
                      'peer_offline_caching',
                      'peer_offline_caching_desc',
                      Icons.cloud_off,
                      themeProvider.peerOfflineCachingEnabled,
                      (value) =>
                          themeProvider.setPeerOfflineCachingEnabled(value),
                    ),
                  ),
                // Sub-option for network module: allow own library caching
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: _buildModuleToggle(
                    context,
                    'allow_library_caching',
                    'allow_library_caching_desc',
                    Icons.share,
                    themeProvider.allowLibraryCaching,
                    (value) => themeProvider.setAllowLibraryCaching(value),
                  ),
                ),
                // Sub-option for network module: connection validation
                if (themeProvider.networkEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: _buildModuleToggle(
                      context,
                      'connection_validation',
                      'connection_validation_desc',
                      Icons.verified_user,
                      themeProvider.connectionValidationEnabled,
                      (value) =>
                          themeProvider.setConnectionValidationEnabled(value),
                    ),
                  ),
                _buildModuleToggle(
                  context,
                  'module_edition_browser',
                  'module_edition_browser_desc',
                  Icons.layers,
                  themeProvider.editionBrowserEnabled,
                  (value) => themeProvider.setEditionBrowserEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'enable_borrowing_module',
                  'borrowing_module_desc',
                  Icons.swap_horiz,
                  themeProvider.canBorrowBooks,
                  (value) => themeProvider.setCanBorrowBooks(value),
                ),
                _buildModuleToggle(
                  context,
                  'module_digital_formats',
                  'module_digital_formats_desc',
                  Icons.tablet_mac,
                  themeProvider.digitalFormatsEnabled,
                  (value) => themeProvider.setDigitalFormatsEnabled(value),
                ),
                _buildMcpModuleToggle(),
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
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

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Security Section
            Text(
              TranslationService.translate(context, 'security') ?? 'Security',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
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
                          : (TranslationService.translate(context, 'not_set') ??
                                'Not set'),
                    ),
                    trailing: TextButton(
                      onPressed: _showChangePasswordDialog,
                      child: Text(
                        TranslationService.translate(context, 'change') ??
                            'Change',
                      ),
                    ),
                  ),
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
                          ? (TranslationService.translate(context, 'enabled') ??
                                'Enabled')
                          : (TranslationService.translate(
                                  context,
                                  'disabled',
                                ) ??
                                'Disabled'),
                    ),
                    trailing: Switch(
                      value: mfaEnabled,
                      onChanged: (val) {
                        if (val) {
                          _setupMfa();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Search Configuration
            _buildSearchConfiguration(context),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Data Management
            Text(
              TranslationService.translate(context, 'content') ?? 'Content',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_calls, color: Colors.blue),
                title: const Text('Gestion de la bibliothèque & Migration'),
                subtitle: const Text(
                  'Importer, exporter ou fusionner vos livres',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/migration-wizard'),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Session / Logout
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
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildMcpModuleToggle() {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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

  Widget _buildThemeSelector(BuildContext context, ThemeProvider themeProvider) {
    ThemeRegistry.initialize();
    final themes = ThemeRegistry.all;
    final currentId = themeProvider.themeStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'theme_title') ?? 'Theme',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
                          : Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.8),
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
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
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
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
            ),
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
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
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

  String _themeDisplayName(BuildContext context, String themeId) {
    final key = 'theme_$themeId';
    return TranslationService.translate(context, key) ??
        ThemeRegistry.get(themeId)?.displayName ??
        themeId;
  }

  Widget _buildModuleToggle(
    BuildContext context,
    String titleKey,
    String descKey,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged, {
    String? tag,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
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
        Text(
          TranslationService.translate(context, 'search_sources') ??
              'Search Sources',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
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
  }) {
    return SwitchListTile(
      secondary: icon != null ? Icon(icon) : null,
      title: Text(title),
      subtitle: Text(
        TranslationService.translate(context, subtitleKey) ?? subtitleKey,
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _updateSearchPreference(String source, bool enabled) async {
    setState(() {
      _searchPrefs[source] = enabled;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);

      // Get profile type from config or ThemeProvider
      final profileType =
          _config?['profile_type'] ??
          Provider.of<ThemeProvider>(context, listen: false).profileType;

      // Use updateProfile which properly syncs to enabled_modules in database
      // This ensures Google Books and other module toggles persist correctly
      await api.updateProfile(
        data: {
          'profile_type': profileType,
          'fallback_preferences': _searchPrefs,
        },
      );

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

    if (apiService.useFfi) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                TranslationService.translate(context, 'two_factor_auth') ??
                    'Two-Factor Authentication',
              ),
            ],
          ),
          content: Text(
            TranslationService.translate(context, 'mfa_requires_server') ??
                'Two-factor authentication is only available when connected to a remote BiblioGenius server. In local mode, your data is already secured on your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TranslationService.translate(context, 'ok') ?? 'OK'),
            ),
          ],
        ),
      );
      return;
    }

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
