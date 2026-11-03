import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../utils/app_constants.dart';
import '../../utils/backup_actions.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Advanced section: AI assistants, the operation log, the experimental
/// hierarchical shelves and the version; then, in a separate zone, the reset.
class AdvancedSettingsSection extends StatefulWidget {
  const AdvancedSettingsSection({super.key});

  @override
  State<AdvancedSettingsSection> createState() =>
      _AdvancedSettingsSectionState();
}

class _AdvancedSettingsSectionState extends State<AdvancedSettingsSection> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
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
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final versionLabel = 'BiblioGenius v$_appVersion';
    // Shown while searching too, when the query is the version or names it.
    final showVersion =
        _appVersion.isNotEmpty &&
        settingsMatchesLabel(context, 'app_version', versionLabel);
    if (!showVersion &&
        !settingsMatches(context, [
          'modules_group_advanced',
          'mcp_integration',
          'mcp_description',
          'module_operation_log_viewer',
          'module_operation_log_desc',
          'enable_taxonomy',
          'enable_taxonomy_desc',
          'system_reset_title',
          'system_reset_subtitle',
        ])) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      name: 'advanced',
      children: [
        _buildMcpModuleToggle(),
        SettingsToggleCard(
          titleKey: 'module_operation_log_viewer',
          descKey: 'module_operation_log_desc',
          icon: Icons.receipt_long_rounded,
          value: themeProvider.operationLogViewerEnabled,
          onChanged: (value) =>
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
                // push, not go: keeps the settings page under
                // it so the log has a real back destination.
                onTap: () => context.push('/operation-log'),
              ),
            ),
          ),
        if (settingsMatches(context, [
          'enable_taxonomy',
          'enable_taxonomy_desc',
        ]))
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SwitchListTile(
              secondary: const Icon(Icons.account_tree),
              title: Text(
                TranslationService.translate(context, 'enable_taxonomy') ??
                    'Hierarchical Tags',
              ),
              subtitle: Text(
                TranslationService.translate(context, 'enable_taxonomy_desc'),
              ),
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
        if (showVersion)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              versionLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (settingsMatches(context, [
          'system_reset_title',
          'system_reset_subtitle',
        ])) ...[
          const SettingsCarefulZoneHeader(),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.shade200),
            ),
            child: ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
              title: Text(
                TranslationService.translate(context, 'system_reset_title'),
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                TranslationService.translate(context, 'system_reset_subtitle'),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.red.shade700),
              onTap: () => BackupActions.showResetDialog(context),
            ),
          ),
        ],
      ],
    );
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
