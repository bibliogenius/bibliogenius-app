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
/// [depth], with a name, an optional second line and a trailing marker.
///
/// For assistive technology the row is one button named after the shelf;
/// [checked] adds a checked state, and a null [onTap] reads as disabled.
/// [subtitleAction] and [actions] are controls of their own (a fold button, a
/// drag handle, a menu): they stay separate nodes inside the row's button, each
/// with its own name, where the painted texts are left out.
class ShelfTreeRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final int depth;
  final bool? checked;
  final bool highlighted;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A control at the end of the second line, at least 44 pt tall. The name
  /// moves down to meet it, so the two lines still read as one block.
  final Widget? subtitleAction;

  /// Replaces [subtitle] and [subtitleAction] on screen for a moment, in the
  /// room they keep: the row does not change height.
  final String? subtitleNotice;

  /// What assistive technology reads as the second line, when the painted
  /// [subtitle] leaves part of it to [subtitleAction].
  final String? semanticSubtitle;

  /// Drawn after [trailing], at the end of the row.
  final List<Widget> actions;

  /// The shelf's picture, drawn before the name at every level, in place
  /// of the plain icon a first-level row shows without one. Decorative.
  final Widget? thumbnail;

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
    this.subtitleAction,
    this.subtitleNotice,
    this.semanticSubtitle,
    this.actions = const [],
    this.thumbnail,
  });

  bool get _hasControls => subtitleAction != null || actions.isNotEmpty;

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
      value: semanticSubtitle ?? subtitle,
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
            constraints: BoxConstraints(
              minHeight: thumbnail != null
                  ? _thumbnailRowHeight
                  : (depth == 0 ? 52 : 48),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: level * shelfTreeIndent,
              ),
              child: Ink(
                decoration: tinted
                    ? BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Row(
                  children: [
                    const SizedBox(width: _rowPadding),
                    if (thumbnail != null) ...[
                      // Greyed with the row it belongs to.
                      Opacity(opacity: enabled ? 1 : 0.38, child: thumbnail),
                      const SizedBox(width: _thumbnailGap),
                    ] else if (level == 0) ...[
                      ExcludeSemantics(
                        child: Icon(
                          Icons.shelves,
                          size: _iconSize,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: _iconGap),
                    ],
                    Expanded(child: _buildLabels(theme, foreground)),
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
          ),
        ),
      ),
    );
  }

  Widget _buildLabels(ThemeData theme, Color foreground) {
    final scheme = theme.colorScheme;
    final action = subtitleAction;
    final title = ExcludeSemantics(
      child: Text(
        name,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: foreground,
          fontWeight: depth == 0 || checked == true
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: onTap != null || legibleSubtitle
          ? scheme.onSurfaceVariant
          : foreground,
    );
    if (action == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            if (subtitle != null)
              ExcludeSemantics(child: Text(subtitle!, style: subtitleStyle)),
          ],
        ),
      );
    }
    // Each piece of the second line is 44 pt tall, the text in its middle,
    // so that they line up beside the action. The name moves down over that
    // margin and a wrapped run up over it, which keeps the lines at their
    // usual gap wherever the wrap falls. Listed bottom-up so that the name is
    // hit first: a tap on it always opens the shelf.
    final lines = Wrap(
      spacing: 8,
      runSpacing: -_actionInset,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (subtitle != null)
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: _actionInset),
              child: Text(subtitle!, style: subtitleStyle),
            ),
          ),
        action,
      ],
    );
    final notice = subtitleNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      verticalDirection: VerticalDirection.up,
      children: [
        if (notice == null)
          lines
        else
          // Over the same room: the row keeps its height under a dragged
          // shelf, so the drop target does not move under the pointer.
          SizedBox(
            width: double.infinity,
            child: Stack(
              children: [
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: lines,
                ),
                Positioned.fill(
                  top: _actionInset,
                  child: ExcludeSemantics(
                    child: Text(
                      notice,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Transform.translate(
          offset: const Offset(0, _actionInset),
          child: title,
        ),
      ],
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

// Row geometry: every level moves [shelfTreeIndent] further right.
const double _rowPadding = 8;
const double _iconSize = 22;
const double _iconGap = 12;
const double _thumbnailGap = 10;
const double _thumbnailRowHeight = 68;

/// What takes a line of small text to the 44 pt of a subtitle action.
const double _actionInset = 14;
