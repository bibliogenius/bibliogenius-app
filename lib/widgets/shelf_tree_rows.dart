import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';

/// Indentation per level of the shelf tree.
const double shelfTreeIndent = 24;

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
class ShelfTreeRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final int depth;
  final bool? checked;
  final bool highlighted;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ShelfTreeRow({
    super.key,
    required this.name,
    this.subtitle,
    this.depth = 0,
    this.checked,
    this.highlighted = false,
    this.trailing,
    this.onTap,
  });

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

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      checked: checked,
      label: name,
      value: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: tinted ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: depth == 0 ? 52 : 48),
            // Sized to its content, so the guide lines span the whole row
            // even when large text makes it taller.
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < level; i++)
                    _GuideLine(color: scheme.outlineVariant),
                  const SizedBox(width: 8),
                  if (depth == 0) ...[
                    Icon(Icons.shelves, size: 22, color: foreground),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                color: enabled
                                    ? scheme.onSurfaceVariant
                                    : foreground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
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

class _GuideLine extends StatelessWidget {
  final Color color;

  const _GuideLine({required this.color});

  @override
  Widget build(BuildContext context) {
    // No height: the line takes the row's, set by [IntrinsicHeight].
    return SizedBox(
      width: shelfTreeIndent,
      child: Center(child: Container(width: 2, color: color)),
    );
  }
}
