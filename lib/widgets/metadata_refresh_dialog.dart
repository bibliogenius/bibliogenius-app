import 'dart:math';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/translation_service.dart';
import 'cached_book_cover.dart';

/// Dialog for comparing fetched metadata with current book data.
/// Shows a field-by-field comparison and lets the user cherry-pick
/// which fields to apply.
///
/// Returns a `Map<String, dynamic>` of selected field updates,
/// or `null` if cancelled.
class MetadataRefreshDialog extends StatefulWidget {
  final Book currentBook;
  final Map<String, String?> fetchedMetadata;

  const MetadataRefreshDialog({
    super.key,
    required this.currentBook,
    required this.fetchedMetadata,
  });

  @override
  State<MetadataRefreshDialog> createState() => _MetadataRefreshDialogState();
}

class _MetadataRefreshDialogState extends State<MetadataRefreshDialog> {
  final Map<String, bool> _selected = {};

  /// Field definitions: key → (label i18n key, current value getter, fetched key)
  static const _fieldKeys = [
    'title',
    'author',
    'summary',
    'publisher',
    'publication_year',
    'cover_url',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-select fields based on comparison logic
    for (final key in _fieldKeys) {
      final current = _getCurrentValue(key);
      final fetched = _getFetchedValue(key);

      if (fetched == null || fetched.isEmpty) {
        // Fetched is empty → hide (not selectable)
        continue;
      }
      if (_valuesEqual(key, current, fetched)) {
        // Identical → show but disabled
        _selected[key] = false;
        continue;
      }
      if (current == null || current.isEmpty) {
        // Current empty, fetched has data → pre-select
        _selected[key] = true;
      } else {
        // Both have different data → show but not pre-selected
        _selected[key] = false;
      }
    }
  }

  String? _getCurrentValue(String key) {
    final book = widget.currentBook;
    return switch (key) {
      'title' => book.title,
      'author' => book.author,
      'summary' => book.summary,
      'publisher' => book.publisher,
      'publication_year' => book.publicationYear?.toString(),
      'cover_url' => book.hasPersistedCover ? book.coverUrl : null,
      _ => null,
    };
  }

  String? _getFetchedValue(String key) {
    var value = widget.fetchedMetadata[key];
    // Normalize publication_year: extract first 4 digits
    if (key == 'publication_year' && value != null && value.length >= 4) {
      value = value.substring(0, min(4, value.length));
    }
    return value;
  }

  bool _valuesEqual(String key, String? current, String? fetched) {
    if (current == null && fetched == null) return true;
    if (current == null || fetched == null) return false;
    if (key == 'publication_year') {
      // Compare as integers
      return int.tryParse(current) == int.tryParse(fetched);
    }
    return current.trim().toLowerCase() == fetched.trim().toLowerCase();
  }

  String _fieldLabel(String key) {
    final i18nKey = switch (key) {
      'title' => 'refresh_field_title',
      'author' => 'refresh_field_author',
      'summary' => 'refresh_field_summary',
      'publisher' => 'refresh_field_publisher',
      'publication_year' => 'refresh_field_year',
      'cover_url' => 'refresh_field_cover',
      _ => key,
    };
    return TranslationService.translate(context, i18nKey) ?? key;
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  Map<String, dynamic> _buildResult() {
    final result = <String, dynamic>{};
    for (final entry in _selected.entries) {
      if (!entry.value) continue;
      final fetched = _getFetchedValue(entry.key);
      if (fetched == null) continue;

      if (entry.key == 'publication_year') {
        result[entry.key] = int.tryParse(fetched);
      } else {
        result[entry.key] = fetched;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        TranslationService.translate(context, 'refresh_metadata_title') ??
            'Update Book Info',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: _buildFieldRows(theme),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _selectedCount > 0
              ? () => Navigator.of(context).pop(_buildResult())
              : null,
          child: Text(
            '${TranslationService.translate(context, 'refresh_apply') ?? 'Apply'}'
            '${_selectedCount > 0 ? ' ($_selectedCount)' : ''}',
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFieldRows(ThemeData theme) {
    final rows = <Widget>[];

    for (final key in _fieldKeys) {
      final current = _getCurrentValue(key);
      final fetched = _getFetchedValue(key);

      // Skip fields where fetched is empty
      if (fetched == null || fetched.isEmpty) continue;

      final identical = _valuesEqual(key, current, fetched);
      final isSelected = _selected[key] ?? false;

      if (identical) {
        // Show as disabled "identical" row
        rows.add(_buildIdenticalRow(key, theme));
      } else if (key == 'cover_url') {
        // Special cover row with thumbnails
        rows.add(_buildCoverRow(key, current, fetched, isSelected, theme));
      } else {
        // Normal comparison row
        rows.add(
            _buildComparisonRow(key, current, fetched, isSelected, theme));
      }
    }

    return rows;
  }

  Widget _buildIdenticalRow(String key, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 40), // Align with checkbox rows
          Text(
            '${_fieldLabel(key)} : ',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            TranslationService.translate(context, 'refresh_identical') ??
                'Same',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String key,
    String? current,
    String? fetched,
    bool isSelected,
    ThemeData theme,
  ) {
    final currentLabel =
        TranslationService.translate(context, 'refresh_current') ?? 'Current';
    final foundLabel =
        TranslationService.translate(context, 'refresh_found') ?? 'Found';
    final emptyLabel =
        TranslationService.translate(context, 'refresh_empty') ?? 'Empty';

    final currentDisplay = (current != null && current.isNotEmpty)
        ? _truncate(current, 80)
        : '($emptyLabel)';
    final fetchedDisplay = _truncate(fetched ?? '', 80);

    return CheckboxListTile(
      value: isSelected,
      onChanged: (val) {
        setState(() => _selected[key] = val ?? false);
      },
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(_fieldLabel(key),
          style: theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$currentLabel : ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              TextSpan(
                text: currentDisplay,
                style: theme.textTheme.bodySmall,
              ),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$foundLabel : ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              TextSpan(
                text: fetchedDisplay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverRow(
    String key,
    String? current,
    String? fetched,
    bool isSelected,
    ThemeData theme,
  ) {
    return CheckboxListTile(
      value: isSelected,
      onChanged: (val) {
        setState(() => _selected[key] = val ?? false);
      },
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(_fieldLabel(key),
          style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            // Current cover
            Column(
              children: [
                Text(
                  TranslationService.translate(context, 'refresh_current') ??
                      'Current',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: (current != null && current.isNotEmpty)
                      ? CachedBookCover(
                          imageUrl: current,
                          width: 50,
                          height: 70,
                        )
                      : Container(
                          width: 50,
                          height: 70,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward, size: 16),
            const SizedBox(width: 16),
            // Fetched cover
            Column(
              children: [
                Text(
                  TranslationService.translate(context, 'refresh_found') ??
                      'Found',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedBookCover(
                    imageUrl: fetched,
                    width: 50,
                    height: 70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }
}
