import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_design.dart';

/// Depend on the theme style ONLY: `ThemeProvider` notifies for many unrelated
/// settings, and these decorations are re-declared by every dashboard section,
/// so a broad `watch` would rebuild them all on each notification.
String _watchThemeStyle(BuildContext context) =>
    context.select<ThemeProvider, String>((provider) => provider.themeStyle);

/// Section header of the dashboard: a gradient accent bar, a tinted icon chip
/// and the title. Shared so every section (book lists, suggestions) speaks the
/// same visual language instead of re-declaring the decoration.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.primary;

    return Semantics(
      header: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppDesign.sectionAccentGradient(
                  _watchThemeStyle(context),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "See all" pill closing a dashboard section: same visual as the inline
/// footer links of the book-list sections, extracted so widget-based
/// sections (e.g. the personal suggestions) can reuse it, with button
/// semantics for screen readers (Rule A1).
class SeeAllLink extends StatelessWidget {
  const SeeAllLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: ScaleOnTap(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDesign.radiusRound),
              border: Border.all(color: primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 16, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section body of the dashboard: a rounded surface card topped by the theme
/// accent gradient. Shared for the same reason as [SectionHeader].
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDesign.radiusXLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          // Accent gradient bar at top
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: AppDesign.sectionAccentGradient(
                _watchThemeStyle(context),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
