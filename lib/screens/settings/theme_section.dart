import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/scaffold_with_nav.dart';
import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../providers/ownership_preference_provider.dart';
import '../../utils/book_filters.dart';
import '../../widgets/contextual_help_sheet.dart';
import '../../themes/base/theme_registry.dart';
import '../../widgets/cover_grid_delegate.dart';
import '../../widgets/cover_size_preview.dart';
import 'settings_scope.dart';
import 'settings_step_slider.dart';
import 'settings_widgets.dart';

/// Display section: theme, text and cover sizes, navigation style and what
/// the home page shows.
class ThemeSettingsSection extends StatelessWidget {
  const ThemeSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final showNavStyle = !usesNavigationRail(context);
    if (!settingsMatches(context, [
      'theme_title',
      'home_page_display',
      'carousel_own_lib_title',
      'carousel_own_lib_desc',
      'carousel_peer_lib_title',
      'carousel_peer_lib_desc',
      'settings_show_not_owned_books',
      'settings_show_not_owned_books_desc',
      if (themeProvider.collectionsEnabled) ...[
        'group_by_collections_title',
        'group_by_collections_desc',
      ],
      'home_cover_size',
      if (!themeProvider.inventoryStatusesEnabled) ...[
        'home_group_by_reading_status',
        'home_group_by_reading_status_desc',
      ],
      if (showNavStyle) ...[
        'nav_style_label',
        'nav_style_side_menu',
        'nav_style_bottom_bar',
      ],
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      name: 'display',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildThemeSelector(context, themeProvider),
              const SizedBox(height: 24),
              _buildTextScaleSlider(context, themeProvider),
              const SizedBox(height: 24),
              _buildCoverSizeSlider(context, themeProvider),
              const SizedBox(height: 24),
              _buildHomeDisplaySection(context, themeProvider),
              if (showNavStyle) ...[
                const SizedBox(height: 24),
                _buildNavStyleSelector(context, themeProvider),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavStyleSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomNav = themeProvider.bottomNavEnabled;

    Widget navOption({
      required bool selected,
      required IconData icon,
      required String labelKey,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Semantics(
          // The highlighted option is the active one; a screen reader is
          // told which, not only the eye.
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : isDark
                    ? theme.colorScheme.surface.withValues(alpha: 0.8)
                    : Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.grey.withValues(alpha: 0.3),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 28,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.translate(context, labelKey),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'nav_style_label'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          TranslationService.translate(context, 'nav_style_desc'),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.grey[500],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            navOption(
              selected: !bottomNav,
              icon: Icons.menu,
              labelKey: 'nav_style_side_menu',
              onTap: () => themeProvider.setBottomNavEnabled(false),
            ),
            const SizedBox(width: 12),
            navOption(
              selected: bottomNav,
              icon: Icons.dock,
              labelKey: 'nav_style_bottom_bar',
              onTap: () => themeProvider.setBottomNavEnabled(true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    ThemeRegistry.initialize();
    final themes = ThemeRegistry.all;
    final currentId = themeProvider.themeStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: themes.map((theme) {
            final isSelected = theme.id == currentId;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: theme.id != themes.last.id ? 8.0 : 0,
                ),
                child: Semantics(
                  // The outlined option is the active theme.
                  button: true,
                  selected: isSelected,
                  child: GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await themeProvider.setThemeStyle(theme.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.previewColor.withValues(alpha: 0.15)
                            : Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? theme.previewColor
                              : Colors.grey.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  theme.previewSecondaryColor,
                                  theme.previewColor,
                                ],
                                stops: const [0.5, 0.5],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _themeDisplayName(context, theme.id),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? theme.previewColor
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTextScaleSlider(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    const steps = [0.85, 1.0, 1.15, 1.3, 1.4];
    final current = themeProvider.textScaleFactor;
    // Find closest step index
    int stepIndex = 0;
    double minDist = (steps[0] - current).abs();
    for (int i = 1; i < steps.length; i++) {
      final dist = (steps[i] - current).abs();
      if (dist < minDist) {
        minDist = dist;
        stepIndex = i;
      }
    }

    String stepLabel(int index) =>
        TranslationService.translate(context, switch (index) {
          0 => 'text_size_small',
          1 => 'text_size_default',
          2 => 'text_size_large',
          3 => 'text_size_larger',
          _ => 'text_size_largest',
        });

    return SettingsStepSlider(
      key: const Key('text_size_slider'),
      title: TranslationService.translate(context, 'text_size'),
      preview: Text(
        'Aa',
        style: TextStyle(
          fontSize: 24 * steps[stepIndex],
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      stepCount: steps.length,
      index: stepIndex,
      valueLabel: stepLabel,
      onChanged: (index) => themeProvider.setTextScaleFactor(steps[index]),
      smallMark: const Text('A', style: TextStyle(fontSize: 12)),
      largeMark: const Text(
        'A',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Size of the covers in the library grids, on the same slider as the text
  /// size. Each step is labelled with the covers a library row holds on this
  /// screen, the measure that tells the steps apart.
  Widget _buildCoverSizeSlider(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    const steps = ThemeProvider.homeCoverExtentSteps;
    final current = steps.indexOf(
      ThemeProvider.nearestHomeCoverStep(themeProvider.homeCoverExtent),
    );
    final gridWidth = coverGridWidthOf(context);
    final phone = coverGridIsPhone(context);

    String stepLabel(int index) => TranslationService.translate(
      context,
      'home_cover_size_per_row',
      params: {
        'count': '${coverGridColumns(gridWidth, steps[index], phone: phone)}',
      },
    );

    return SettingsStepSlider(
      key: const Key('cover_size_slider'),
      title: TranslationService.translate(context, 'home_cover_size'),
      preview: CoverSizePreview(coverSize: steps[current]),
      stepCount: steps.length,
      index: current,
      valueLabel: stepLabel,
      onChanged: (index) => themeProvider.setHomeCoverExtent(steps[index]),
      smallMark: const Icon(Icons.apps, size: 16),
      largeMark: const Icon(Icons.crop_portrait, size: 22),
    );
  }

  /// Home page display: the top strip (Activity / suggestions), the
  /// ownership filter and how the covers grid is grouped.
  Widget _buildHomeDisplaySection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'home_page_display'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.new_releases_outlined),
          title: Text(
            TranslationService.translate(context, 'carousel_own_lib_title'),
          ),
          subtitle: Text(
            TranslationService.translate(context, 'carousel_own_lib_desc'),
          ),
          value: !themeProvider.carouselHiddenOwnLib,
          onChanged: (value) => themeProvider.setCarouselHiddenOwnLib(!value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.new_releases),
          title: Text(
            TranslationService.translate(context, 'carousel_peer_lib_title'),
          ),
          subtitle: Text(
            TranslationService.translate(context, 'carousel_peer_lib_desc'),
          ),
          value: !themeProvider.carouselHiddenPeerLib,
          onChanged: (value) => themeProvider.setCarouselHiddenPeerLib(!value),
        ),
        // The ownership axis of the library filter, as a switch (ADR-063).
        // On = "everything", off = the possession default; the menu's third
        // value, "not owned", reads as off here and turning the switch on
        // from it lands on "everything", which is the only value the switch
        // promises.
        Consumer<OwnershipPreferenceProvider>(
          builder: (context, prefs, _) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(
              TranslationService.translate(
                context,
                'settings_show_not_owned_books',
              ),
            ),
            subtitle: Text(
              TranslationService.translate(
                context,
                'settings_show_not_owned_books_desc',
              ),
            ),
            value: prefs.scope == OwnershipScope.all,
            onChanged: (value) =>
                prefs.setScope(value ? OwnershipScope.all : null),
          ),
        ),
        // Only with the collections module, which it depends on.
        if (themeProvider.collectionsEnabled)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.auto_stories),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'group_by_collections_title',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const HelpAffordance(topicId: 'group_by_collections'),
              ],
            ),
            subtitle: Text(
              TranslationService.translate(
                context,
                'group_by_collections_desc',
              ),
            ),
            value: themeProvider.groupByCollections,
            onChanged: (value) => themeProvider.setGroupByCollections(value),
          ),
        // Inventory statuses replace the reading ones, which the sections
        // are built on.
        if (!themeProvider.inventoryStatusesEnabled)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.view_agenda_outlined),
            title: Text(
              TranslationService.translate(
                context,
                'home_group_by_reading_status',
              ),
            ),
            subtitle: Text(
              TranslationService.translate(
                context,
                'home_group_by_reading_status_desc',
              ),
            ),
            value: themeProvider.groupByReadingStatus,
            onChanged: themeProvider.setGroupByReadingStatus,
          ),
      ],
    );
  }

  String _themeDisplayName(BuildContext context, String themeId) {
    final key = 'theme_$themeId';
    return TranslationService.translate(context, key) ??
        ThemeRegistry.get(themeId)?.displayName ??
        themeId;
  }
}
