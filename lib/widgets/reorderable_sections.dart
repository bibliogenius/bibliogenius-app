import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/translation_service.dart';

/// Configuration for a single section within a [ReorderableSections] widget.
///
/// Each section has a unique [id] used as a persistence key, display metadata
/// (title, icon, gradient), and a [builder] that produces the section content.
class SectionConfig {
  /// Unique key used for persistence, e.g. 'monthly_progress'.
  final String id;

  /// Already-translated title string displayed in the section header.
  final String title;

  /// Icon displayed in the gradient badge next to the title.
  final IconData icon;

  /// Gradient applied to the icon badge container.
  final Gradient gradient;

  /// Builds the section content. Only called in normal (non-edit) mode.
  final Widget Function(BuildContext) builder;

  /// Whether this section is visible by default (before user customization).
  final bool defaultVisible;

  /// Optional help text shown via a tooltip info icon in the section header.
  final String? helpText;

  /// Optional subtitle displayed below the section title as a short caption.
  final String? subtitle;

  const SectionConfig({
    required this.id,
    required this.title,
    required this.icon,
    required this.gradient,
    required this.builder,
    this.defaultVisible = true,
    this.helpText,
    this.subtitle,
  });
}

/// A generic widget that renders a list of sections which can be reordered
/// via drag-and-drop and individually hidden or shown.
///
/// User preferences (order and visibility) are persisted in SharedPreferences
/// using [pageKey] as a namespace prefix. This makes the widget reusable
/// across different screens (statistics, dashboard, etc.).
///
/// In normal mode, only visible sections are rendered in the user-defined order.
/// In edit mode, all sections are shown (collapsed) with drag handles and
/// visibility toggles.
class ReorderableSections extends StatefulWidget {
  /// Prefix for SharedPreferences keys, e.g. 'statistics' or 'dashboard'.
  final String pageKey;

  /// The full list of available sections for this page.
  final List<SectionConfig> sections;

  /// Optional fixed header rendered above the reorderable sections
  /// (e.g. summary cards that should not be reorderable).
  final Widget? header;

  /// Called when the user toggles edit mode on or off.
  final ValueChanged<bool>? onEditModeChanged;

  /// Called when the user resets sections to defaults.
  /// Use this to also reset related state (e.g. summary card order).
  final VoidCallback? onReset;

  const ReorderableSections({
    super.key,
    required this.pageKey,
    required this.sections,
    this.header,
    this.onEditModeChanged,
    this.onReset,
  });

  @override
  State<ReorderableSections> createState() => _ReorderableSectionsState();
}

class _ReorderableSectionsState extends State<ReorderableSections> {
  bool _editMode = false;
  bool _prefsLoaded = false;

  /// Current ordering of section IDs.
  late List<String> _sectionOrder;

  /// Set of section IDs that are currently hidden.
  late Set<String> _hiddenSections;

  @override
  void initState() {
    super.initState();
    _sectionOrder = widget.sections.map((s) => s.id).toList();
    _hiddenSections = widget.sections
        .where((s) => !s.defaultVisible)
        .map((s) => s.id)
        .toSet();
    _loadPreferences();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  String get _orderKey => '${widget.pageKey}_section_order';
  String get _hiddenKey => '${widget.pageKey}_hidden_sections';

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final orderJson = prefs.getString(_orderKey);
    final hiddenJson = prefs.getString(_hiddenKey);

    if (!mounted) return;

    setState(() {
      if (orderJson != null) {
        final savedOrder = List<String>.from(json.decode(orderJson) as List);
        // Merge: keep saved order for known IDs, append any new sections at the end
        final knownIds = widget.sections.map((s) => s.id).toSet();
        final validSaved = savedOrder.where(knownIds.contains).toList();
        final newIds = knownIds.difference(validSaved.toSet());
        _sectionOrder = [...validSaved, ...newIds];
      }

      if (hiddenJson != null) {
        _hiddenSections = Set<String>.from(json.decode(hiddenJson) as List);
      }

      _prefsLoaded = true;
    });
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey, json.encode(_sectionOrder));
  }

  Future<void> _saveHidden() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _hiddenKey,
      json.encode(_hiddenSections.toList()),
    );
  }

  Future<void> _resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderKey);
    await prefs.remove(_hiddenKey);

    if (!mounted) return;

    setState(() {
      _sectionOrder = widget.sections.map((s) => s.id).toList();
      _hiddenSections = widget.sections
          .where((s) => !s.defaultVisible)
          .map((s) => s.id)
          .toSet();
    });
    widget.onReset?.call();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  SectionConfig? _configById(String id) {
    for (final s in widget.sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<SectionConfig> get _orderedSections {
    final configs = <SectionConfig>[];
    for (final id in _sectionOrder) {
      final config = _configById(id);
      if (config != null) configs.add(config);
    }
    return configs;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _sectionOrder.removeAt(oldIndex);
      _sectionOrder.insert(newIndex, id);
    });
    _saveOrder();
  }

  void _toggleVisibility(String sectionId) {
    setState(() {
      if (_hiddenSections.contains(sectionId)) {
        _hiddenSections.remove(sectionId);
      } else {
        _hiddenSections.add(sectionId);
      }
    });
    _saveHidden();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return widget.header != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [widget.header!],
            )
          : const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.header != null) widget.header!,
        _buildEditToggleBar(context),
        if (_editMode) _buildEditModeList(context) else _buildNormalList(context),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Edit toggle bar
  // ---------------------------------------------------------------------------

  Widget _buildEditToggleBar(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_editMode) ...[
            TextButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(
                TranslationService.translate(context, 'sections_reset'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                setState(() => _editMode = false);
                widget.onEditModeChanged?.call(false);
              },
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                TranslationService.translate(context, 'sections_edit_done'),
              ),
            ),
          ] else ...[
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: TranslationService.translate(
                context,
                'tooltip_edit_sections',
              ),
              onPressed: () {
                setState(() => _editMode = true);
                widget.onEditModeChanged?.call(true);
              },
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Normal mode: visible sections with full content
  // ---------------------------------------------------------------------------

  Widget _buildNormalList(BuildContext context) {
    final visible =
        _orderedSections.where((s) => !_hiddenSections.contains(s.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in visible) ...[
          _buildSectionHeader(context, section),
          const SizedBox(height: 12),
          section.builder(context),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Edit mode: all sections collapsed, drag-and-drop reordering
  // ---------------------------------------------------------------------------

  Widget _buildEditModeList(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            TranslationService.translate(context, 'sections_drag_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _sectionOrder.length,
          onReorder: _onReorder,
          proxyDecorator: _proxyDecorator,
          itemBuilder: (context, index) {
            final sectionId = _sectionOrder[index];
            final config = _configById(sectionId);
            if (config == null) {
              return SizedBox.shrink(key: ValueKey(sectionId));
            }
            final isHidden = _hiddenSections.contains(sectionId);

            return _EditModeTile(
              key: ValueKey(sectionId),
              index: index,
              config: config,
              isHidden: isHidden,
              onToggleVisibility: () => _toggleVisibility(sectionId),
            );
          },
        ),
      ],
    );
  }

  /// Decoration applied to the item being dragged.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final elevationValue = Tween<double>(begin: 0, end: 6).evaluate(animation);
        return Material(
          elevation: elevationValue,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }

  // ---------------------------------------------------------------------------
  // Section header (shared pattern from statistics_screen)
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(BuildContext context, SectionConfig config) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: config.gradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(config.icon, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  config.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (config.helpText != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: config.helpText!,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(color: Colors.white, fontSize: 13),
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
        if (config.subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Text(
              config.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Edit mode tile (private widget)
// =============================================================================

/// A single row in edit mode showing the section header with a drag handle
/// on the left and a visibility toggle on the right.
class _EditModeTile extends StatelessWidget {
  final int index;
  final SectionConfig config;
  final bool isHidden;
  final VoidCallback onToggleVisibility;

  const _EditModeTile({
    super.key,
    required this.index,
    required this.config,
    required this.isHidden,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Opacity(
      opacity: isHidden ? 0.4 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: TranslationService.translate(
                      context,
                      'sections_drag_hint',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.drag_handle,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Section icon badge
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: config.gradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(config.icon, size: 16, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                // Section title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isHidden)
                        Text(
                          TranslationService.translate(
                            context,
                            'sections_hidden',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                // Visibility toggle
                IconButton(
                  icon: Icon(
                    isHidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: TranslationService.translate(
                    context,
                    'tooltip_toggle_section',
                  ),
                  onPressed: onToggleVisibility,
                  color: isHidden
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
