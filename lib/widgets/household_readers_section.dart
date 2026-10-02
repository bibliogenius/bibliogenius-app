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
        AccountSyncInfoNote(text: t('household_note')),
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
        RadioGroup<String>(
          groupValue: currentId,
          onChanged: (id) {
            if (id == null || busy) return;
            _apply(context, () => provider.selectReader(id));
          },
          child: Column(
            children: [
              for (final reader in readers)
                Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: AppDesign.spacingXs,
                  ),
                  decoration: accountSyncCardDecoration(context),
                  child: RadioListTile<String>(
                    value: reader.id,
                    title: Text(
                      reader.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: reader.id == currentId
                        ? Text(t('household_reads_here'))
                        : null,
                    // The visible control is an icon; assistive tech gets the
                    // action and the name.
                    secondary: Semantics(
                      button: true,
                      enabled: !busy,
                      label: '${t('rename')}, ${reader.name}',
                      child: ExcludeSemantics(
                        child: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: t('rename'),
                          onPressed: busy
                              ? null
                              : () => _rename(context, reader.id, reader.name),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
