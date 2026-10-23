import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/scaffold_with_nav.dart';
import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../themes/base/theme_registry.dart';
import 'settings_scope.dart';

/// Theme accordion (theme + text size)
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('theme_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.palette_outlined),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'theme_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
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
                _buildHomeDisplaySection(context, themeProvider),
                if (showNavStyle) ...[
                  const SizedBox(height: 24),
                  _buildNavStyleSelector(context, themeProvider),
                ],
              ],
            ),
          ),
        ],
      ),
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

    String stepLabel(int index) {
      switch (index) {
        case 0:
          return TranslationService.translate(context, 'text_size_small') ??
              'Small';
        case 1:
          return TranslationService.translate(context, 'text_size_default') ??
              'Default';
        default:
          return TranslationService.translate(context, 'text_size_large') ??
              'Large';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'text_size') ?? 'Text Size',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              // Preview text
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 24 * steps[stepIndex],
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stepLabel(stepIndex),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 8),
              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: stepIndex.toDouble(),
                  min: 0,
                  max: (steps.length - 1).toDouble(),
                  divisions: steps.length - 1,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (value) {
                    HapticFeedback.lightImpact();
                    themeProvider.setTextScaleFactor(steps[value.round()]);
                  },
                ),
              ),
              // Min/max labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'A',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    Text(
                      'A',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Home page display: the top strip (Activity / suggestions), the grouping
  /// of the covers grid by reading status and the size of the covers.
  Widget _buildHomeDisplaySection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    const sizeKeys = [
      'home_cover_size_small',
      'home_cover_size_medium',
      'home_cover_size_large',
    ];
    const sizeIcons = [Icons.apps, Icons.grid_view, Icons.crop_portrait];
    final steps = ThemeProvider.homeCoverExtentSteps;
    // A stored value outside the steps snaps to the closest one.
    var selected = steps.first;
    for (final step in steps) {
      if ((step - themeProvider.homeCoverExtent).abs() <
          (selected - themeProvider.homeCoverExtent).abs()) {
        selected = step;
      }
    }

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
        const SizedBox(height: 8),
        Text(TranslationService.translate(context, 'home_cover_size')),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < steps.length; i++)
                ButtonSegment<double>(
                  value: steps[i],
                  icon: Icon(sizeIcons[i]),
                  label: Text(
                    TranslationService.translate(context, sizeKeys[i]),
                  ),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (values) {
              HapticFeedback.lightImpact();
              themeProvider.setHomeCoverExtent(values.first);
            },
          ),
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
