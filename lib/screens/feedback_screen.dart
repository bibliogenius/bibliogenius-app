import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/genie_app_bar.dart';

/// Beta Bug Reporting Screen
/// Allows users to report bugs and open GitHub issues directly
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();

  bool _isBug = true; // true = bug, false = feature request
  bool _isSubmitting = false;

  // App info - fetched asynchronously
  String _appVersion = 'Unknown';

  // Hub URL from the single source of truth (ApiService.hubUrl)
  static String get _hubUrl => ApiService.hubUrl;

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
          _appVersion = info.version;
        });
      }
    } catch (e) {
      debugPrint('Error getting package info: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  String _getPlatformInfo() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  String _generateMarkdown() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final locale = themeProvider.locale.languageCode;

    final buffer = StringBuffer();

    if (_isBug) {
      buffer.writeln('**Describe the bug**');
      buffer.writeln(_descriptionController.text.trim());
      buffer.writeln();

      if (_stepsController.text.trim().isNotEmpty) {
        buffer.writeln('**To Reproduce**');
        buffer.writeln(_stepsController.text.trim());
        buffer.writeln();
      }

      buffer.writeln('**Environment**');
      buffer.writeln('- App Version: $_appVersion');
      buffer.writeln('- OS: ${_getPlatformInfo()}');
      buffer.writeln('- Language: $locale');
    } else {
      buffer.writeln(
        '**Is your feature request related to a problem? Please describe.**',
      );
      buffer.writeln(_descriptionController.text.trim());
      buffer.writeln();

      if (_stepsController.text.trim().isNotEmpty) {
        buffer.writeln('**Describe the solution you\'d like**');
        buffer.writeln(_stepsController.text.trim());
      }
    }

    return buffer.toString();
  }

  /// Submit feedback to Hub API which creates a Jira issue
  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

      final response = await http.post(
        Uri.parse('$_hubUrl/api/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': _isBug ? 'bug' : 'feature',
          'title': _titleController.text.trim(),
          'description':
              _descriptionController.text.trim() +
              (_stepsController.text.trim().isNotEmpty
                  ? '\n\n${_isBug ? "Steps to reproduce:" : "Proposed solution:"}\n${_stepsController.text.trim()}'
                  : ''),
          'context': {
            'app_version': _appVersion,
            'os': _getPlatformInfo(),
            'language': themeProvider.locale.languageCode,
          },
        }),
      );

      if (mounted) {
        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          AppSnackBar.success(
            context,
            '${TranslationService.translate(context, 'feedback_success')} (${data['issueKey']})',
          );
          Navigator.of(context).pop();
        } else {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? 'Unknown error');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'feedback_error_sending')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _copyToClipboard() async {
    if (!_formKey.currentState!.validate()) return;

    final markdown = _generateMarkdown();
    await Clipboard.setData(ClipboardData(text: markdown));

    if (mounted) {
      AppSnackBar.success(
        context,
        TranslationService.translate(context, 'feedback_copied'),
      );
    }
  }

  Future<void> _share() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final markdown = _generateMarkdown();

    await Share.share(
      '$title\n\n$markdown\n\nReported via BiblioGenius App',
      subject: 'BiblioGenius Feedback: $title',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'feedback_title'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Beta badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                          context,
                          'feedback_beta_notice',
                        ),
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Type selector
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(
                      TranslationService.translate(
                        context,
                        'feedback_type_bug',
                      ),
                    ),
                    icon: const Icon(Icons.bug_report),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      TranslationService.translate(
                        context,
                        'feedback_type_feature',
                      ),
                    ),
                    icon: const Icon(Icons.lightbulb_outline),
                  ),
                ],
                selected: {_isBug},
                onSelectionChanged: (selection) {
                  setState(() => _isBug = selection.first);
                },
              ),

              const SizedBox(height: 20),

              // Title field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'feedback_title_label',
                  ),
                  hintText: TranslationService.translate(
                    context,
                    'feedback_title_hint',
                  ),
                  prefixIcon: const Icon(Icons.title),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return TranslationService.translate(
                      context,
                      'feedback_title_required',
                    );
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'feedback_description_label',
                  ),
                  hintText: TranslationService.translate(
                    context,
                    'feedback_description_hint',
                  ),
                  prefixIcon: const Icon(Icons.description),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return TranslationService.translate(
                      context,
                      'feedback_description_required',
                    );
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Steps / Additional info field
              TextFormField(
                controller: _stepsController,
                decoration: InputDecoration(
                  labelText: _isBug
                      ? TranslationService.translate(
                          context,
                          'feedback_steps_label',
                        )
                      : TranslationService.translate(
                          context,
                          'feedback_solution_label',
                        ),
                  hintText: _isBug
                      ? TranslationService.translate(
                          context,
                          'feedback_steps_hint',
                        )
                      : TranslationService.translate(
                          context,
                          'feedback_solution_hint',
                        ),
                  prefixIcon: Icon(
                    _isBug
                        ? Icons.format_list_numbered
                        : Icons.tips_and_updates,
                  ),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 24),

              // System info preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'feedback_auto_collected',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• App: v$_appVersion\n'
                      '• OS: ${_getPlatformInfo()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitFeedback,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  TranslationService.translate(context, 'feedback_submit'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: Text(
                        TranslationService.translate(context, 'feedback_copy'),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share),
                      label: Text(
                        TranslationService.translate(context, 'feedback_share'),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
