import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/book_refresh_notifier.dart';
import '../providers/household_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'account_sync_summary_sheet.dart';
import 'household_reader_name_dialog.dart';

/// Readers of the account: one shared library, one reading state per person.
///
/// Everyone enrolled in the account shares the catalogue; picking "who reads
/// on this device" gives each person their own statuses, reading dates and
/// ratings, while the wishlist stays common. Until a reader is picked the
/// device keeps the shared state, exactly as before.
class HouseholdReadersSection extends StatelessWidget {
  const HouseholdReadersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final readers = provider.readers;
    final currentId = provider.currentReaderId;
    final busy = provider.busy;
    String t(String key) => TranslationService.translate(context, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountSyncSectionHeader(t('household_title')),
        AccountSyncSectionSubtitle(t('household_subtitle')),
        // Before the first reader the section is one explanation and one
        // button; the list and its notes come with the readers.
        if (readers.isEmpty) AccountSyncInfoNote(text: t('household_note')),
        // The rows carry no radio: while nobody reads here, say what a tap
        // on a name does.
        if (readers.isNotEmpty && currentId == null)
          AccountSyncSectionSubtitle(t('household_pick_prompt')),
        for (final reader in readers)
          _ReaderRow(
            name: reader.name,
            selected: reader.id == currentId,
            readsHereLabel: t('household_reads_here'),
            onSelect: busy || reader.id == currentId
                ? null
                : () => _apply(context, () => provider.selectReader(reader.id)),
            // The visible controls are icons; assistive tech gets the action
            // and the name.
            actions: [
              _ReaderAction(
                label: '${t('rename')}, ${reader.name}',
                tooltip: t('rename'),
                icon: Icons.edit_outlined,
                onPressed: busy
                    ? null
                    : () => _rename(context, reader.id, reader.name),
              ),
              _ReaderAction(
                label: '${t('delete')}, ${reader.name}',
                tooltip: t('delete'),
                icon: Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
                onPressed: busy
                    ? null
                    : () => _delete(context, reader.id, reader.name),
              ),
            ],
          ),
        if (readers.isNotEmpty) ...[
          const SizedBox(height: AppDesign.spacingSm),
          // An older build on another device of the account cannot show these
          // readings: the note stays as long as readers exist.
          AccountSyncInfoNote(
            text: t('household_update_note'),
            icon: Icons.system_update_alt,
          ),
        ],
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.person_add_alt),
          onPressed: busy ? null : () => _addReader(context),
          label: Text(
            t(readers.isEmpty ? 'household_create_me' : 'household_add_reader'),
          ),
          style: accountSyncSecondaryActionStyle(context),
        ),
        if (currentId != null)
          TextButton.icon(
            icon: const Icon(Icons.group_outlined),
            onPressed: busy
                ? null
                : () => _apply(context, provider.leaveReader),
            label: Text(t('household_leave_reader')),
          ),
      ],
    );
  }

  Future<void> _addReader(BuildContext context) async {
    final provider = context.read<HouseholdProvider>();
    final name = await showHouseholdReaderNameDialog(
      context,
      titleKey: provider.readers.isEmpty
          ? 'household_create_me'
          : 'household_add_reader',
    );
    if (name == null || !context.mounted) return;
    await _apply(context, () => provider.createReader(name));
  }

  Future<void> _rename(BuildContext context, String id, String current) async {
    final provider = context.read<HouseholdProvider>();
    final name = await showHouseholdReaderNameDialog(
      context,
      titleKey: 'household_rename_title',
      confirmKey: 'save',
      initialName: current,
    );
    if (name == null || name == current || !context.mounted) return;
    await _apply(context, () => provider.renameReader(id, name));
  }

  /// Removing a reader erases their readings on every device of the account,
  /// and any device can do it: the consequence is spelled out before.
  Future<void> _delete(BuildContext context, String id, String name) async {
    final provider = context.read<HouseholdProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(
            ctx,
            'household_delete_title',
            params: {'name': name},
          ),
        ),
        content: Text(
          TranslationService.translate(ctx, 'household_delete_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(TranslationService.translate(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _apply(context, () => provider.deleteReader(id));
  }

  /// Every list on screen shows the reading state of the current reader, so
  /// a change of reader has to reach them all.
  Future<void> _apply(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    final ok = await action();
    if (!context.mounted) return;
    if (ok) {
      context.read<BookRefreshNotifier>().refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'household_error'),
          ),
        ),
      );
    }
  }
}

/// One reader of the account: a person, shown by their initial where the
/// device rows show a device glyph. Tapping the name makes them the reader
/// of this device; the row of the current one carries the "reads here" mark.
class _ReaderRow extends StatelessWidget {
  final String name;
  final bool selected;
  final String readsHereLabel;

  /// Null while a request is in flight and on the current reader.
  final VoidCallback? onSelect;
  final List<Widget> actions;

  const _ReaderRow({
    required this.name,
    required this.selected,
    required this.readsHereLabel,
    required this.onSelect,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial = name.trim().characters.firstOrNull?.toUpperCase() ?? '?';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppDesign.spacingXs),
      decoration: accountSyncCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              // The readers form a single-choice list: one node per reader
              // with its checked state, the icon actions stay separate nodes.
              child: Semantics(
                container: true,
                inMutuallyExclusiveGroup: true,
                checked: selected,
                label: selected ? '$name, $readsHereLabel' : name,
                onTap: onSelect,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onSelect,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesign.spacingMd),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? cs.primary
                                : cs.primary.withValues(alpha: 0.12),
                          ),
                          // Decorative: the name next to it scales, the
                          // initial stays inside its circle.
                          child: Text(
                            initial,
                            textScaler: TextScaler.noScaling,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: selected ? cs.onPrimary : cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDesign.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (selected) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.menu_book,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: AppDesign.spacingXs),
                                    Flexible(
                                      child: Text(
                                        readsHereLabel,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...actions,
            const SizedBox(width: AppDesign.spacingXs),
          ],
        ),
      ),
    );
  }
}

/// Icon action on a reader row, announced with the reader's name.
class _ReaderAction extends StatelessWidget {
  final String label;
  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  const _ReaderAction({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: ExcludeSemantics(
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          color: color,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
