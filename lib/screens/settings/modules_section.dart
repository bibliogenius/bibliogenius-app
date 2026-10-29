import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Features accordion: the quick presets, then the switch of each module
/// that has no section of its own. A module's options live in the section
/// of what they change (loans, home page display, notifications).
class ModulesSettingsSection extends StatelessWidget {
  const ModulesSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'modules',
      'quick_presets',
      'quick_presets_desc',
      'preset_reader',
      'preset_librarian',
      'preset_bookseller',
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
      'hangman_module',
      'hangman_module_desc',
      'network_gamification',
      'network_gamification_desc',
      'share_gamification_stats',
      'share_gamification_stats_desc',
      'collections_module',
      'collections_module_desc',
      'commerce_module',
      'commerce_module_desc',
      'audio_module',
      'audio_module_desc',
      'speech_to_text_setting',
      'speech_to_text_setting_desc',
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsAccordion(
      name: 'modules',
      icon: Icons.extension_outlined,
      titleKey: 'modules',
      children: [
        if (settingsMatches(context, [
          'quick_presets',
          'quick_presets_desc',
          'preset_reader',
          'preset_librarian',
          'preset_bookseller',
        ]))
          _buildPresets(context, themeProvider),
        SettingsToggleCard(
          titleKey: 'quotes_module',
          descKey: 'quotes_module_desc',
          icon: Icons.format_quote,
          value: themeProvider.quotesEnabled,
          onChanged: (value) => themeProvider.setQuotesEnabled(value),
          helpTopicId: 'quotes_module',
        ),
        SettingsToggleCard(
          titleKey: 'gamification_module',
          descKey: 'gamification_desc',
          icon: Icons.emoji_events,
          value: themeProvider.gamificationEnabled,
          onChanged: (value) => themeProvider.setGamificationEnabled(value),
          helpTopicId: 'gamification_module',
        ),
        if (themeProvider.gamificationEnabled && themeProvider.networkEnabled)
          SettingsToggleCard(
            titleKey: 'network_gamification',
            descKey: 'network_gamification_desc',
            icon: Icons.leaderboard,
            value: themeProvider.networkGamificationEnabled,
            onChanged: (value) =>
                themeProvider.setNetworkGamificationEnabled(value),
            helpTopicId: 'network_gamification',
            indent: 16,
          ),
        if (themeProvider.networkGamificationEnabled &&
            themeProvider.gamificationEnabled &&
            themeProvider.networkEnabled)
          SettingsToggleCard(
            titleKey: 'share_gamification_stats',
            descKey: 'share_gamification_stats_desc',
            icon: Icons.share,
            value: themeProvider.shareGamificationStats,
            onChanged: (value) =>
                themeProvider.setShareGamificationStats(value),
            helpTopicId: 'share_gamification_stats',
            indent: 32,
          ),
        SettingsToggleCard(
          titleKey: 'games_module',
          descKey: 'games_module_desc',
          icon: Icons.sports_esports,
          value: themeProvider.gamesEnabled,
          onChanged: (value) => themeProvider.setGamesEnabled(value),
          helpTopicId: 'games_module',
        ),
        if (themeProvider.gamesEnabled) ...[
          SettingsToggleCard(
            titleKey: 'memory_game_module',
            descKey: 'memory_game_module_desc',
            icon: Icons.auto_stories,
            value: themeProvider.memoryGameEnabled,
            onChanged: (value) => themeProvider.setMemoryGameEnabled(value),
            helpTopicId: 'memory_game',
            indent: 16,
          ),
          SettingsToggleCard(
            titleKey: 'sliding_puzzle_module',
            descKey: 'sliding_puzzle_module_desc',
            icon: Icons.grid_view,
            value: themeProvider.slidingPuzzleEnabled,
            onChanged: (value) => themeProvider.setSlidingPuzzleEnabled(value),
            helpTopicId: 'sliding_puzzle',
            indent: 16,
          ),
          SettingsToggleCard(
            titleKey: 'hangman_module',
            descKey: 'hangman_module_desc',
            icon: Icons.text_fields,
            value: themeProvider.hangmanEnabled,
            onChanged: (value) => themeProvider.setHangmanEnabled(value),
            helpTopicId: 'hangman',
            indent: 16,
          ),
        ],
        SettingsToggleCard(
          titleKey: 'collections_module',
          descKey: 'collections_module_desc',
          icon: Icons.collections_bookmark,
          value: themeProvider.collectionsEnabled,
          onChanged: (value) => themeProvider.setCollectionsEnabled(value),
          helpTopicId: 'collections',
        ),
        SettingsToggleCard(
          titleKey: 'commerce_module',
          descKey: 'commerce_module_desc',
          icon: Icons.storefront,
          value: themeProvider.commerceEnabled,
          onChanged: (value) => themeProvider.setCommerceEnabled(value),
          helpTopicId: 'commerce_module',
        ),
        SettingsToggleCard(
          titleKey: 'audio_module',
          descKey: 'audio_module_desc',
          icon: Icons.headphones,
          value: themeProvider.audioEnabled,
          onChanged: (value) => themeProvider.setAudioEnabled(value),
          helpTopicId: 'audio',
        ),
        SettingsToggleCard(
          titleKey: 'speech_to_text_setting',
          descKey: 'speech_to_text_setting_desc',
          icon: Icons.mic,
          value: themeProvider.speechToTextEnabled,
          onChanged: (value) => themeProvider.setSpeechToTextEnabled(value),
          helpTopicId: 'speech_to_text',
        ),
      ],
    );
  }

  /// The presets come first: each one sets the modules below at once.
  Widget _buildPresets(BuildContext context, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(context, 'quick_presets') ??
                'Quick Presets',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            TranslationService.translate(context, 'quick_presets_desc') ??
                'Apply a configuration adapted to your usage:',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PresetButton(
                  presetName: 'reader',
                  label:
                      TranslationService.translate(context, 'preset_reader') ??
                      'Reader',
                  icon: Icons.menu_book,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetButton(
                  presetName: 'librarian',
                  label:
                      TranslationService.translate(
                        context,
                        'preset_librarian',
                      ) ??
                      'Librarian',
                  icon: Icons.local_library,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetButton(
                  presetName: 'bookseller',
                  label:
                      TranslationService.translate(
                        context,
                        'preset_bookseller',
                      ) ??
                      'Bookseller',
                  icon: Icons.storefront,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.presetName,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String presetName;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Applies the preset at once: an action, so a button.
      button: true,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final themeProvider = context.read<ThemeProvider>();
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
}
