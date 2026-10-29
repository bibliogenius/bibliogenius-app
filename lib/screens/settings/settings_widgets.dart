import 'package:flutter/material.dart';

import '../../services/translation_service.dart';
import '../../widgets/contextual_help_sheet.dart';
import 'settings_scope.dart';

/// One settings section: a card holding a collapsed accordion, opened on its
/// own while a search is running.
class SettingsAccordion extends StatelessWidget {
  const SettingsAccordion({
    super.key,
    required this.name,
    required this.icon,
    required this.titleKey,
    required this.children,
    this.expandedCrossAxisAlignment,
  });

  /// Stable name of the section, used to key its tile.
  final String name;
  final IconData icon;
  final String titleKey;
  final List<Widget> children;
  final CrossAxisAlignment? expandedCrossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        // A new key when the search starts or ends, so the tile picks up
        // initiallyExpanded again.
        key: ValueKey('${name}_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        expandedCrossAxisAlignment: expandedCrossAxisAlignment,
        leading: Icon(icon),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, titleKey),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: children,
      ),
    );
  }
}

/// Header of the four groups the sections are sorted into.
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.titleKey, {super.key});

  final String titleKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          TranslationService.translate(context, titleKey),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Sub-header inside a section, with a rule below it.
class SettingsSubheader extends StatelessWidget {
  const SettingsSubheader(this.titleKey, {super.key});

  final String titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              TranslationService.translate(context, titleKey),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
}

/// Opens the separate zone at the bottom of a section that holds what cannot
/// be undone (restoring a backup, resetting the app).
class SettingsCarefulZoneHeader extends StatelessWidget {
  const SettingsCarefulZoneHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, thickness: 1, color: color.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'settings_careful_zone',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A switch in its own card, hidden when a search does not match its title or
/// description.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    super.key,
    required this.titleKey,
    required this.descKey,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.helpTopicId,
    this.indent = 0,
  });

  final String titleKey;
  final String descKey;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? helpTopicId;

  /// Extra left inset, for a toggle that depends on the one above it.
  final double indent;

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [titleKey, descKey])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: EdgeInsets.fromLTRB(16 + indent, 0, 16, 12),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Row(
          children: [
            Flexible(
              child: Text(TranslationService.translate(context, titleKey)),
            ),
            if (helpTopicId != null) ...[
              const SizedBox(width: 4),
              HelpAffordance(topicId: helpTopicId!),
            ],
          ],
        ),
        subtitle: Text(TranslationService.translate(context, descKey)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
