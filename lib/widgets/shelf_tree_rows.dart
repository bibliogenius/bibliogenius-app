import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';

/// Indentation per level of the shelf tree.
const double shelfTreeIndent = 24;

/// Width of the [ShelfTreeRow.leading] slot: a 44 pt target, or the same
/// space left empty so that names line up.
const double shelfTreeLeadingWidth = 44;

/// Deepest level that still gets its own indentation. Rows below it stay at
/// this depth and name their parent path instead, so a deep tree does not
/// push names off a phone screen.
const int shelfTreeMaxIndentDepth = 2;

/// One shelf as a tree lists it: its depth and the names above it.
class ShelfTreeEntry {
  final Tag tag;
  final int depth;
  final List<String> ancestors;

  const ShelfTreeEntry(this.tag, this.depth, this.ancestors);
}

/// The whole tree, unfolded, parents before their children, every level in
/// [compareShelves] order. Built on [Tag.childrenIndex], so a cycle or a
/// vanished parent merged from sync lists at the first level instead of
/// hiding a branch.
List<ShelfTreeEntry> flattenShelfTree(List<Tag> tags) {
  final children = Tag.childrenIndex(tags);
  final out = <ShelfTreeEntry>[];
  final seen = <String>{};
  void walk(String? parentId, int depth, List<String> ancestors) {
    for (final tag in children[parentId] ?? const <Tag>[]) {
      // The index never makes a tag its own descendant; the guard only
      // keeps a malformed list (duplicate ids) from looping.
      if (!seen.add(tag.id)) continue;
      out.add(ShelfTreeEntry(tag, depth, ancestors));
      walk(tag.id, depth + 1, [...ancestors, tag.name]);
    }
  }

  walk(null, 0, const []);
  return out;
}

/// "in Genre › Polar", or null for a first-level shelf.
String? shelfParentPath(BuildContext context, List<String> ancestors) {
  if (ancestors.isEmpty) return null;
  return TranslationService.translate(
    context,
    'shelf_in_path',
  ).replaceAll('{path}', ancestors.join(' › '));
}

/// A small section title above a group of rows or chips ("Recent").
class ShelfSectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const ShelfSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(8, 12, 8, 4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A full-width shelf row: tappable over its whole width, indented by
/// [depth] with a guide line per level, a name, an optional second line and
/// a trailing marker.
///
/// For assistive technology the row is one button named after the shelf;
/// [checked] adds a checked state, and a null [onTap] reads as disabled.
/// [leading] and [actions] are controls of their own (a fold chevron, a drag
/// handle, a menu): they stay separate nodes inside the row's button, each
/// with its own name, where the painted texts are left out.
class ShelfTreeRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final int depth;
  final bool? checked;
  final bool highlighted;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Drawn before the name, in a slot [shelfTreeLeadingWidth] wide. The
  /// guide lines of the levels below move with it, so a child still hangs
  /// under its parent's icon.
  final Widget? leading;

  /// Drawn after [trailing], at the end of the row.
  final List<Widget> actions;

  /// Draws [subtitle] at full legibility even when the row is not
  /// tappable: for a note that tells a disabled row apart, such as the
  /// current place of a shelf being moved.
  final bool legibleSubtitle;

  const ShelfTreeRow({
    super.key,
    required this.name,
    this.subtitle,
    this.depth = 0,
    this.checked,
    this.highlighted = false,
    this.trailing,
    this.onTap,
    this.legibleSubtitle = false,
    this.leading,
    this.actions = const [],
  });

  bool get _hasControls => leading != null || actions.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final tinted = highlighted || checked == true;
    final level = depth.clamp(0, shelfTreeMaxIndentDepth);
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : tinted
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    // A sub-shelf is tinted from just after its own guide line, so the
    // lines of its parents stay outside the tint; a first-level shelf from
    // the edge.
    final shift = leading == null ? 0.0 : shelfTreeLeadingWidth;
    final tintStart = level == 0 ? 0.0 : _guideX(level, shift) + 1;
    final radius = level == 0
        ? BorderRadius.circular(12)
        : const BorderRadius.horizontal(right: Radius.circular(12));

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      checked: checked,
      label: name,
      value: subtitle,
      onTap: onTap,
      excludeSemantics: !_hasControls,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // The row's own node carries the tap: a second one here would
          // split off as a nameless node next to the row's controls.
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: depth == 0 ? 52 : 48),
            // Sized to its content, so the guide lines span the whole row
            // even when large text makes it taller.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (level > 0)
                    SizedBox(
                      width: tintStart,
                      child: CustomPaint(
                        painter: _GuideLinesPainter(
                          levels: level,
                          shift: shift,
                          color: scheme.outlineVariant,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Ink(
                      decoration: tinted
                          ? BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: radius,
                            )
                          : null,
                      child: Row(
                        children: [
                          if (level == 0) const SizedBox(width: _rowPadding),
                          if (leading != null)
                            SizedBox(
                              width: shelfTreeLeadingWidth,
                              child: leading,
                            ),
                          if (level == 0) ...[
                            ExcludeSemantics(
                              child: Icon(
                                Icons.shelves,
                                size: _iconSize,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(width: _iconGap),
                          ] else
                            SizedBox(
                              width: leading == null ? _childTextGap : 4,
                            ),
                          Expanded(
                            child: ExcludeSemantics(
                              child: _buildLabels(theme, foreground),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ],
                          ...actions,
                          SizedBox(width: actions.isEmpty ? 8 : 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabels(ThemeData theme, Color foreground) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: foreground,
              fontWeight: depth == 0 || checked == true
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: onTap != null || legibleSubtitle
                    ? scheme.onSurfaceVariant
                    : foreground,
              ),
            ),
        ],
      ),
    );
  }
}

/// The ring a row shows when its shelf is not chosen, the filled disc with
/// a check mark when it is.
class ShelfCheckMarker extends StatelessWidget {
  final bool checked;

  const ShelfCheckMarker({super.key, required this.checked});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? scheme.primary : null,
        border: checked ? null : Border.all(color: scheme.outline, width: 2),
      ),
      child: checked
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

// Row geometry. A first-level row shows the shelf icon; a sub-shelf hangs
// its guide line under the right edge of that icon and starts its name just
// past it, so a child always reads right of its parent, then each deeper
// level moves [shelfTreeIndent] further.
const double _rowPadding = 8;
const double _iconSize = 22;
const double _iconGap = 12;
const double _childTextGap = 20;

/// Centre of the guide line of level [k] (1 for a first-level parent),
/// [shift] further right when the rows carry a leading slot.
double _guideX(int k, [double shift = 0]) =>
    _rowPadding + shift + _iconSize - 3 + (k - 1) * shelfTreeIndent;

/// One vertical line per level above the row, over its whole height.
class _GuideLinesPainter extends CustomPainter {
  final int levels;
  final double shift;
  final Color color;

  const _GuideLinesPainter({
    required this.levels,
    this.shift = 0,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var k = 1; k <= levels; k++) {
      final x = _guideX(k, shift);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GuideLinesPainter old) =>
      old.levels != levels || old.shift != shift || old.color != color;
}
