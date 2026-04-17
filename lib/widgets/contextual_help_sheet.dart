import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/help_registry.dart';
import '../services/translation_service.dart';

/// A contextual help sheet that displays help content for a specific screen.
/// Uses the same UI pattern as QuickActionsSheet for consistency.
class ContextualHelpSheet extends StatelessWidget {
  /// The translation key for the help title (e.g., 'help_network_title')
  final String titleKey;

  /// The translation key for the help content (e.g., 'help_network_content')
  final String contentKey;

  /// Optional list of help tips with icon and text
  final List<HelpTip>? tips;

  /// Optional [HelpRegistry] topic id. When provided AND [showSeeMoreLink]
  /// is true, the "See all help" link deep-links to `/help?topic=<id>`
  /// so the matching accordion is expanded and scrolled into view.
  final String? topicId;

  /// Whether to render the "See all help topics" link at the bottom.
  /// Set to `false` for inline-only topics that don't appear in `/help`.
  final bool showSeeMoreLink;

  const ContextualHelpSheet({
    super.key,
    required this.titleKey,
    required this.contentKey,
    this.tips,
    this.topicId,
    this.showSeeMoreLink = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.help_outline,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  TranslationService.translate(context, titleKey) ?? titleKey,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: TranslationService.translate(context, 'close'),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main content
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              ),
            ),
            child: Text(
              TranslationService.translate(context, contentKey) ?? contentKey,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),

          // Tips section
          if (tips != null && tips!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              TranslationService.translate(context, 'help_tips_title') ??
                  'Tips',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            ...tips!.map((tip) => _buildTipItem(context, tip, isDark)),
          ],

          const SizedBox(height: 16),
          if (showSeeMoreLink)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.help_outline, size: 16),
                label: Text(
                  TranslationService.translate(context, 'help_see_all') ??
                      'See all help topics',
                ),
                onPressed: () {
                  Navigator.pop(context);
                  final target = topicId == null
                      ? '/help'
                      : '/help?topic=$topicId';
                  GoRouter.of(context).go(target);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTipItem(BuildContext context, HelpTip tip, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: tip.color.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(tip.icon, color: tip.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(context, tip.titleKey) ??
                      tip.titleKey,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                if (tip.descriptionKey != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    TranslationService.translate(
                          context,
                          tip.descriptionKey!,
                        ) ??
                        tip.descriptionKey!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A help tip with icon, title, and optional description
class HelpTip {
  final IconData icon;
  final Color color;
  final String titleKey;
  final String? descriptionKey;

  const HelpTip({
    required this.icon,
    required this.color,
    required this.titleKey,
    this.descriptionKey,
  });
}

/// Helper function to show the contextual help sheet
void showContextualHelp(
  BuildContext context, {
  required String titleKey,
  required String contentKey,
  List<HelpTip>? tips,
  String? topicId,
  bool showSeeMoreLink = true,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => ContextualHelpSheet(
      titleKey: titleKey,
      contentKey: contentKey,
      tips: tips,
      topicId: topicId,
      showSeeMoreLink: showSeeMoreLink,
    ),
  );
}

/// Opens the contextual help sheet for a registered [HelpRegistry] topic.
/// Looks up the topic by [topicId] and forwards its title/desc keys.
/// FAQ topics get the "See all help" link; inline topics do not.
/// If the id is unknown, the call is a no-op.
void showHelpForTopic(BuildContext context, String topicId) {
  final topic = HelpRegistry.findById(topicId);
  if (topic == null) return;
  showContextualHelp(
    context,
    titleKey: topic.titleKey,
    contentKey: topic.descKey,
    topicId: topic.id,
    showSeeMoreLink: topic.inFaq,
  );
}

/// A small "?" affordance designed to live next to a settings entry
/// (typically inside a [ListTile]'s `trailing`). Tapping it opens the
/// contextual help sheet for the matching [HelpRegistry] topic.
///
/// If the topic id is unknown, the widget renders an empty SizedBox.
class HelpAffordance extends StatelessWidget {
  final String topicId;

  const HelpAffordance({super.key, required this.topicId});

  @override
  Widget build(BuildContext context) {
    final topic = HelpRegistry.findById(topicId);
    if (topic == null) return const SizedBox.shrink();

    final tooltip = TranslationService.translate(context, 'help');
    return IconButton(
      icon: const Icon(Icons.help_outline, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: Theme.of(context).colorScheme.primary,
      onPressed: () => showHelpForTopic(context, topicId),
    );
  }
}

/// A floating help button that can be added to any screen
class ContextualHelpButton extends StatelessWidget {
  final String titleKey;
  final String contentKey;
  final List<HelpTip>? tips;

  const ContextualHelpButton({
    super.key,
    required this.titleKey,
    required this.contentKey,
    this.tips,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showContextualHelp(
          context,
          titleKey: titleKey,
          contentKey: contentKey,
          tips: tips,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.blue.withOpacity(0.2)
                : Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, color: Colors.blue, size: 18),
              const SizedBox(width: 6),
              Text(
                TranslationService.translate(context, 'help') ?? 'Help',
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon-only help button for use in app bars
class ContextualHelpIconButton extends StatelessWidget {
  final String titleKey;
  final String contentKey;
  final List<HelpTip>? tips;
  final Color? iconColor;

  const ContextualHelpIconButton({
    super.key,
    required this.titleKey,
    required this.contentKey,
    this.tips,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline, color: iconColor ?? Colors.white),
      tooltip: TranslationService.translate(context, 'help') ?? 'Help',
      onPressed: () => showContextualHelp(
        context,
        titleKey: titleKey,
        contentKey: contentKey,
        tips: tips,
      ),
    );
  }
}
