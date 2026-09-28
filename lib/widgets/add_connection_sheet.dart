import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Content of the "add a connection" bottom sheet.
///
/// Two kinds of people, kept apart on screen: another BiblioGenius library
/// (scan their code, or invite them with this library's own invitation) and
/// a contact without the app, managed by hand. The callbacks close the sheet
/// and navigate; the sheet itself only lays out the choice.
class AddConnectionSheet extends StatelessWidget {
  final VoidCallback onScan;

  /// Opens the plain contact form (a person without the app).
  final VoidCallback onEnterAddress;
  final VoidCallback onInvite;

  const AddConnectionSheet({
    super.key,
    required this.onScan,
    required this.onEnterAddress,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Scrolls when the sheet's capped height (or a landscape phone) is
    // shorter than the content, instead of overflowing.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.people_alt,
                    color: Colors.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                        context,
                        'add_connection_title',
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              TranslationService.translate(context, 'add_connection_intro'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              text: TranslationService.translate(
                context,
                'add_connection_section',
              ),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              key: const Key('actionScanQr'),
              icon: Icons.qr_code_scanner,
              color: Colors.blue,
              title: TranslationService.translate(
                context,
                'add_connection_scan',
              ),
              subtitle: TranslationService.translate(
                context,
                'add_connection_scan_hint',
              ),
              onTap: onScan,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              key: const Key('actionInvite'),
              icon: Icons.qr_code_2,
              color: theme.colorScheme.primary,
              emphasized: true,
              title: TranslationService.translate(
                context,
                'add_connection_invite',
              ),
              subtitle: TranslationService.translate(
                context,
                'add_connection_invite_hint',
              ),
              onTap: onInvite,
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              text: TranslationService.translate(
                context,
                'add_connection_contact_section',
              ),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              key: const Key('actionEnterManually'),
              icon: Icons.person_add_alt_1,
              color: Colors.orange,
              title: TranslationService.translate(
                context,
                'add_connection_contact',
              ),
              subtitle: TranslationService.translate(
                context,
                'add_connection_contact_hint',
              ),
              onTap: onEnterAddress,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Horizontal tile in the style of the network banner: tinted card, icon
/// badge, title, one-line hint and a chevron. Same footprint for the three
/// actions; [emphasized] paints the primary one with the brand gradient.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool emphasized;
  final VoidCallback onTap;

  const _ActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A2E35);
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF5A7A82);

    // One node per tile: title and hint as the name, a button role, the tap.
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: emphasized
                  ? LinearGradient(
                      colors: isDark
                          ? [
                              color.withValues(alpha: 0.18),
                              color.withValues(alpha: 0.08),
                            ]
                          : [
                              color.withValues(alpha: 0.10),
                              color.withValues(alpha: 0.03),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: emphasized
                  ? null
                  : color.withValues(alpha: isDark ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.25 : 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Wraps freely: a narrow phone or a large text scale
                      // must never cut the hint, the sheet scrolls instead.
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 22, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
