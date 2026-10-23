import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/contextual_help_sheet.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import 'settings_scope.dart';

/// Search Sources accordion
class SearchSourcesSettingsSection extends StatefulWidget {
  const SearchSourcesSettingsSection({super.key});

  @override
  State<SearchSourcesSettingsSection> createState() =>
      _SearchSourcesSettingsSectionState();
}

class _SearchSourcesSettingsSectionState
    extends State<SearchSourcesSettingsSection> {
  SettingsData get _data => settingsDataOf(context);

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, ['search_sources'])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('search_sources_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.saved_search),
        title: Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, 'search_sources'),
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
                _data.searchPrefs['inventaire'] ?? true,
                (val) => _updateSearchPreference('inventaire', val),
                icon: Icons.language,
              ),
              _buildSwitchTile(
                context,
                'Bibliothèque Nationale (BNF)',
                'source_bnf_desc',
                _data.searchPrefs['bnf'] ?? bnfDefault,
                (val) => _updateSearchPreference('bnf', val),
                icon: Icons.account_balance,
              ),
              _buildSwitchTile(
                context,
                'OpenLibrary',
                'source_openlibrary_desc',
                _data.searchPrefs['openlibrary'] ?? true,
                (val) => _updateSearchPreference('openlibrary', val),
                icon: Icons.local_library,
              ),
              _buildSwitchTile(
                context,
                'Google Books',
                'source_google_desc',
                _data.searchPrefs['google_books'] ?? googleDefault,
                (val) => _updateSearchPreference('google_books', val),
                icon: Icons.search,
                tag: TranslationService.translate(
                  context,
                  'google_books_advanced_tag',
                ),
              ),
              if ((_data.searchPrefs['google_books'] ?? googleDefault) &&
                  _data.googleBooksApiKey.isEmpty)
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
              if (_data.searchPrefs['google_books'] ?? googleDefault)
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
                            _data.showGoogleAdvanced
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
                            () => _data.showGoogleAdvanced =
                                !_data.showGoogleAdvanced,
                          ),
                        ),
                      ),
                      if (_data.showGoogleAdvanced) ...[
                        const SizedBox(height: 4),
                        TextField(
                          controller: _data.apiKeyController,
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
    final key = _data.apiKeyController.text.trim();
    if (key == _data.googleBooksApiKey) return;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateProfile(
        data: {
          'api_keys': {'google_books': key},
        },
      );

      setState(() => _data.googleBooksApiKey = key);

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
      _data.searchPrefs[source] = enabled;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);

      // Use updateProfile which properly syncs to enabled_modules in database.
      // This ensures Google Books and other module toggles persist correctly.
      await api.updateProfile(
        data: {'fallback_preferences': _data.searchPrefs},
      );

      if (_data.userStatus != null) {
        if (_data.userStatus!['config'] == null) {
          _data.userStatus!['config'] = {};
        }
        _data.userStatus!['config']['fallback_preferences'] = _data.searchPrefs;
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
}
