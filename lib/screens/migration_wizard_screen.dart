import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';

class MigrationWizardScreen extends StatefulWidget {
  const MigrationWizardScreen({super.key});

  @override
  State<MigrationWizardScreen> createState() => _MigrationWizardScreenState();
}

class _MigrationWizardScreenState extends State<MigrationWizardScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'migration_wizard_screen_title'),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
        ),
        child: SafeArea(
          child: _isProcessing
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                        context,
                        TranslationService.translate(
                          context,
                          'migration_section_import_title',
                        ),
                        TranslationService.translate(
                          context,
                          'migration_section_import_subtitle',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: TranslationService.translate(
                          context,
                          'migration_card_csv_title',
                        ),
                        description: TranslationService.translate(
                          context,
                          'migration_card_csv_subtitle',
                        ),
                        icon: Icons.import_contacts,
                        onTap: () => _handleCsvImport(),
                        color: Colors.orange.shade400,
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader(
                        context,
                        TranslationService.translate(
                          context,
                          'migration_section_organisation_title',
                        ),
                        TranslationService.translate(
                          context,
                          'migration_section_organisation_subtitle',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildMigrationCard(
                        context,
                        title: TranslationService.translate(
                          context,
                          'migration_card_shelves_title',
                        ),
                        description: TranslationService.translate(
                          context,
                          'migration_card_shelves_subtitle',
                        ),
                        icon: Icons.folder_special,
                        onTap: () => context.push('/shelves-management'),
                        color: Colors.blue.shade400,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.blueGrey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCsvImport() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final importFailedMsg = TranslationService.translate(
      context,
      'migration_import_failed',
    );
    final errorPrefix = TranslationService.translate(
      context,
      'migration_error_prefix',
    );

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isProcessing = true);

      final file = result.files.first;
      final response = kIsWeb
          ? await apiService.importBooks(file.bytes!, filename: file.name)
          : await apiService.importBooks(file.path!);

      if (mounted) {
        setState(() => _isProcessing = false);
        if (response.statusCode == 200) {
          final imported = response.data['imported'];
          final successMsg = TranslationService.translate(
            context,
            'migration_import_success',
            params: {'count': '$imported'},
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMsg),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(response.data['error'] ?? importFailedMsg);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorPrefix : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
