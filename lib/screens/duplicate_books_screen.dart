import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/duplicate_books_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../theme/app_design.dart';

/// Maintenance screen for duplicate books (ADR-070).
///
/// Two devices that each held the same book before they shared an account
/// minted two ids for it, and the sync merges by id, so the joined library
/// carries both. This screen previews the duplicates and merges them, in two
/// families the reader must be able to tell apart: a shared ISBN is certain
/// and merges in one gesture, a shared title and author is only likely and is
/// accepted one group at a time.
class DuplicateBooksScreen extends StatelessWidget {
  const DuplicateBooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DuplicateBooksProvider>(
      create: (_) => DuplicateBooksProvider()..refresh(),
      child: const _DuplicateBooksView(),
    );
  }
}

class _DuplicateBooksView extends StatelessWidget {
  const _DuplicateBooksView();

  String _t(BuildContext context, String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(_t(context, 'duplicates_title')),
        ),
      ),
      body: Consumer<DuplicateBooksProvider>(
        builder: (context, provider, _) {
          // Built through the builder form: a library that joined an account
          // can carry hundreds of groups, and only the visible cards should be
          // mounted. The list itself is heterogeneous (notes, headers, cards),
          // so it is composed first and indexed here.
          final rows = _body(context, provider);
          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDesign.maxContentWidth,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  itemCount: rows.length,
                  itemBuilder: (_, index) => rows[index],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _body(BuildContext context, DuplicateBooksProvider provider) {
    final theme = Theme.of(context);

    if (provider.isScanning && provider.scan == null) {
      return [
        const SizedBox(height: AppDesign.spacingXl),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: AppDesign.spacingMd),
        Center(child: Text(_t(context, 'duplicates_scanning'))),
      ];
    }

    if (provider.error != null) {
      return [
        _Note(
          icon: Icons.error_outline,
          text: _t(context, 'duplicates_error'),
          tone: theme.colorScheme.error,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        Center(
          child: FilledButton(
            onPressed: provider.isBusy ? null : provider.refresh,
            child: Text(_t(context, 'retry')),
          ),
        ),
      ];
    }

    return [
      _Note(icon: Icons.info_outline, text: _t(context, 'duplicates_intro')),
      if (provider.lastReport != null) ...[
        const SizedBox(height: AppDesign.spacingMd),
        _Note(
          icon: Icons.check_circle_outline,
          text: _reportText(context, provider.lastReport!),
          tone: theme.colorScheme.primary,
        ),
      ],
      if (!provider.hasAnything) ...[
        const SizedBox(height: AppDesign.spacingXl),
        Center(
          child: Text(
            _t(context, 'duplicates_none'),
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ],
      if (provider.automatic.isNotEmpty) ...[
        const SizedBox(height: AppDesign.spacingLg),
        _SectionHeader(_t(context, 'duplicates_certain_section')),
        Text(
          _t(
            context,
            'duplicates_certain_summary',
            params: {
              'groups': '${provider.automatic.length}',
              'books': '${provider.booksRemovedByAutomatic}',
            },
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        FilledButton.icon(
          onPressed: provider.isBusy
              ? null
              : () => _confirmAndMerge(
                  context,
                  provider,
                  body: _t(
                    context,
                    'duplicates_confirm_all_body',
                    params: {'books': '${provider.booksRemovedByAutomatic}'},
                  ),
                  run: provider.mergeAutomatic,
                ),
          icon: const Icon(Icons.merge_type),
          label: Text(_t(context, 'duplicates_merge_all')),
        ),
        const SizedBox(height: AppDesign.spacingMd),
        for (final group in provider.automatic)
          _GroupCard(group: group, onMerge: null),
      ],
      if (provider.proposed.isNotEmpty) ...[
        const SizedBox(height: AppDesign.spacingLg),
        _SectionHeader(_t(context, 'duplicates_probable_section')),
        Text(
          _t(context, 'duplicates_probable_hint'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        for (final group in provider.proposed)
          _GroupCard(
            group: group,
            onMerge: provider.isBusy
                ? null
                : () => _confirmAndMerge(
                    context,
                    provider,
                    body: _t(
                      context,
                      'duplicates_confirm_one_body',
                      params: {'title': group.canonical.title},
                    ),
                    run: () => provider.mergeGroup(group.key),
                  ),
          ),
      ],
      const SizedBox(height: AppDesign.spacingXl),
    ];
  }

  String _reportText(BuildContext context, frb.FrbMergeReport report) {
    return _t(
      context,
      'duplicates_report',
      params: {
        'books': '${report.booksRemoved}',
        'copies': '${report.copiesCollapsed}',
      },
    );
  }

  Future<void> _confirmAndMerge(
    BuildContext context,
    DuplicateBooksProvider provider, {
    required String body,
    required Future<bool> Function() run,
  }) async {
    // Captured before the dialog: after it, this context has crossed an async
    // gap and may no longer be mounted.
    final messenger = ScaffoldMessenger.of(context);
    final failureText = _t(context, 'duplicates_error');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(dialogContext, 'duplicates_confirm_title')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body),
              const SizedBox(height: AppDesign.spacingMd),
              Text(_t(dialogContext, 'duplicates_confirm_replicates')),
              const SizedBox(height: AppDesign.spacingSm),
              Text(_t(dialogContext, 'duplicates_confirm_backup')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t(dialogContext, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t(dialogContext, 'duplicates_confirm_cta')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await run();
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(failureText)));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A short explanatory strip. The icon is decorative: the sentence carries the
/// meaning on its own, so a screen reader loses nothing.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// One duplicate group: the row that survives, then the rows folded into it.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onMerge});

  final frb.FrbDuplicateGroup group;
  final VoidCallback? onMerge;

  String _t(BuildContext context, String key) =>
      TranslationService.translate(context, key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canonical = group.canonical;

    return Card(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canonical.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (canonical.author != null && canonical.author!.isNotEmpty)
              Text(canonical.author!, style: theme.textTheme.bodySmall),
            if (canonical.isbn != null && canonical.isbn!.isNotEmpty)
              Text(
                'ISBN ${canonical.isbn}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: AppDesign.spacingSm),
            _Line(
              label: _t(context, 'duplicates_kept_label'),
              value: canonical.createdAt,
            ),
            for (final duplicate in group.duplicates)
              _Line(
                label: _t(context, 'duplicates_removed_label'),
                value: duplicate.createdAt,
              ),
            if (onMerge != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(
                  onPressed: onMerge,
                  child: Text(_t(context, 'duplicates_merge_one')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$label  ${_shortDate(value)}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  /// The creation instant is what tells two rows apart on screen, and the day
  /// is enough for that. Cut rather than parsed: the column is an ISO string
  /// and a malformed one must still render something.
  static String _shortDate(String isoDate) =>
      isoDate.length >= 10 ? isoDate.substring(0, 10) : isoDate;
}
