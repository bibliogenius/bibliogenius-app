import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/status_badge.dart';
import '../providers/theme_provider.dart';
import 'package:go_router/go_router.dart';
import '../utils/avatars.dart';
import '../widgets/avatar_customizer.dart';
import '../models/avatar_config.dart';
import '../services/translation_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userStatus;
  Map<String, dynamic>? _config;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final statusRes = await apiService.getUserStatus();
      final configRes = await apiService.getLibraryConfig();
      
      if (mounted) {
        setState(() {
          _userStatus = statusRes.data;
          _config = configRes.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportData() async {
    try {
      ScaffoldMessenger.of(
        context,
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(TranslationService.translate(context, 'preparing_backup'))));

      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.exportData();

      final directory = await getTemporaryDirectory();
      final filename =
          'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(response.data);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'My BiblioGenius Backup');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${TranslationService.translate(context, 'export_fail')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(title: TranslationService.translate(context, 'profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('${TranslationService.translate(context, 'error')}: $_error'))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_userStatus == null) return Center(child: Text(TranslationService.translate(context, 'no_data')));

    final level = _userStatus!['level'] as String;
    final loansCount = _userStatus!['loans_count'] as int;
    final editsCount = _userStatus!['edits_count'] as int;
    final progress = (_userStatus!['next_level_progress'] as num).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const SizedBox(height: 20),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              final avatar = availableAvatars.firstWhere(
                (a) => a.id == themeProvider.currentAvatarId,
                orElse: () => availableAvatars.first,
              );
              
              return Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: avatar.themeColor, width: 4),
                      color: themeProvider.avatarConfig?.style == 'genie'
                          ? Color(int.parse('FF${themeProvider.avatarConfig?.genieBackground ?? "fbbf24"}', radix: 16))
                          : Colors.grey[100],
                    ),
                    child: ClipOval(
                      child: themeProvider.avatarConfig?.style == 'genie'
                          ? Image.asset(
                              'assets/genie_mascot.jpg',
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              themeProvider.avatarConfig?.toUrl(size: 120, format: 'png') ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Image.asset(avatar.assetPath),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _showAvatarPicker(context, themeProvider),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(TranslationService.translate(context, 'librarian'), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          StatusBadge(level: level, size: 32),
          const SizedBox(height: 32),

          // Progress Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(context, 'next_level_progress'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toInt()}% ${TranslationService.translate(context, 'to_next_level')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  TranslationService.translate(context, 'loans'),
                  loansCount.toString(),
                  Icons.book,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  TranslationService.translate(context, 'edits'),
                  editsCount.toString(),
                  Icons.edit,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Profile Settings
          Text(
            TranslationService.translate(context, 'profile_settings'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(TranslationService.translate(context, 'profile_type')),
                  subtitle: Text(_config?['profile_type'] == 'individual' ? TranslationService.translate(context, 'individual') : TranslationService.translate(context, 'professional')),
                  trailing: DropdownButton<String>(
                    value: _config?['profile_type'],
                    underline: Container(),
                    items: [
                      DropdownMenuItem(value: 'individual', child: Text(TranslationService.translate(context, 'individual'))),
                      DropdownMenuItem(value: 'professional', child: Text(TranslationService.translate(context, 'professional'))),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      try {
                        final api = Provider.of<ApiService>(context, listen: false);
                        await api.updateProfile(profileType: value);
                        _fetchStatus(); // Refresh to get updated config (including side effects)
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(TranslationService.translate(context, 'profile_updated'))),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${TranslationService.translate(context, 'error_updating_profile')}: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
                if (_config?['profile_type'] == 'individual')
                  SwitchListTile(
                    title: Text(TranslationService.translate(context, 'show_borrowed_books')),
                    subtitle: Text(TranslationService.translate(context, 'show_borrowed_subtitle')),
                    value: _config?['show_borrowed_books'] ?? false,
                    onChanged: (value) async {
                      try {
                        final api = Provider.of<ApiService>(context, listen: false);
                        // We need to update the library config
                        await api.updateLibraryConfig(
                          name: _config!['name'] ?? 'My Library', // Correct key is 'name' not 'library_name'
                          description: _config!['description'], // Correct key is 'description'
                          showBorrowedBooks: value,
                          shareLocation: _config!['share_location'],
                        );
                        _fetchStatus();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${TranslationService.translate(context, 'error_updating_setting')}: $e')),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Data Management
          Text(
            TranslationService.translate(context, 'data_management'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _exportData,
            icon: const Icon(Icons.download),
            label: Text(TranslationService.translate(context, 'export_backup')),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['csv', 'txt'],
                );

                if (result != null && result.files.single.path != null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(TranslationService.translate(context, 'importing_books'))),
                    );
                  }

                  final apiService = Provider.of<ApiService>(
                    context,
                    listen: false,
                  );
                  final response = await apiService.importBooks(
                    result.files.single.path!,
                  );

                  if (context.mounted) {
                    if (response.statusCode == 200) {
                      final imported = response.data['imported'];
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Successfully imported $imported books!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${TranslationService.translate(context, 'import_fail')}: ${response.data['error']}',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${TranslationService.translate(context, 'error_picking_file')}: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.upload_file),
            label: Text(TranslationService.translate(context, 'import_csv')),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 32),

          const SizedBox(height: 32),
          // App Settings button (formerly Reinstall)
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: Text(TranslationService.translate(context, 'settings_dialog_title')),
                      content: Text(
                        TranslationService.translate(context, 'settings_dialog_body'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(TranslationService.translate(context, 'cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(TranslationService.translate(context, 'edit_settings')),
                        ),
                      ],
                    ),
              );

              if (confirmed == true && mounted) {
                final themeProvider = Provider.of<ThemeProvider>(
                  context,
                  listen: false,
                );
                await themeProvider.resetSetup();
                if (mounted) {
                  context.go('/setup');
                }
              }
            },
            icon: const Icon(Icons.settings),
            label: Text(TranslationService.translate(context, 'app_settings')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final authService = Provider.of<AuthService>(context, listen: false);
              await authService.logout();
              if (mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout),
            label: Text(TranslationService.translate(context, 'logout')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  void _showAvatarPicker(BuildContext context, ThemeProvider themeProvider) {
    // Create a local copy of the config to avoid updating the provider immediately
    // This allows the user to cancel changes
    AvatarConfig currentConfig = themeProvider.avatarConfig ?? AvatarConfig.defaultConfig;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          TranslationService.translate(context, 'customize_avatar'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AvatarCustomizer(
                      initialConfig: currentConfig,
                      onConfigChanged: (newConfig) {
                        setState(() {
                          currentConfig = newConfig;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            // Show loading indicator if needed, or just close and update
                            final api = Provider.of<ApiService>(context, listen: false);
                            await themeProvider.setAvatarConfig(currentConfig, apiService: api);
                            
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(TranslationService.translate(context, 'avatar_updated'))),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${TranslationService.translate(context, 'error_saving_avatar')}: $e')),
                              );
                            }
                          }
                        },
                        child: Text(TranslationService.translate(context, 'save_changes'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
