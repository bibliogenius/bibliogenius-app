import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/translation_service.dart';

/// What a reader sees before sending one of their lists to someone.
///
/// The two halves of sharing did not name each other: the export dropped a
/// `.yml` into the system share sheet with nothing said about what it was,
/// while the import accepted a file OR a paste. So this panel says what the
/// recipient gets, promises them nothing enters their library without a
/// confirmation (which is true: the import previews first), and offers BOTH
/// transports the import understands. Copying matters more than it looks:
/// between two people already talking, pasting into the conversation is the
/// natural gesture, and the app could read a paste long before it could
/// produce one.
///
/// Presentation only. The caller owns the data and the file, which is what
/// keeps this testable without a network or a temp directory: it is handed a
/// finished YAML and a callback.
class CollectionShareSheet extends StatelessWidget {
  const CollectionShareSheet({
    super.key,
    required this.collectionName,
    required this.bookCount,
    required this.yaml,
    required this.onShare,
    this.languages = const [],
  });

  final String collectionName;
  final int bookCount;

  /// The exported list, verbatim. Copied as-is: the import reads a paste
  /// without touching it.
  final String yaml;

  /// Declared reading languages, or empty. An absent declaration is honest;
  /// an empty line reads as a defect.
  final List<String> languages;

  /// Sends the file. Left to the caller because building it is I/O.
  final VoidCallback onShare;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: yaml));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'collection_share_copied'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Scrollable: at 200% text this content is taller than a bottom sheet on
    // a phone, and a fixed Column clips it (measured: 396 pixels over on a
    // 400x700 viewport). Growing and scrolling is the only rendering that
    // keeps the promise readable at every text size (RGAA 4.1 / WCAG 1.4.4).
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  TranslationService.translate(
                    context,
                    'collection_share_title',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                collectionName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                TranslationService.translate(
                  context,
                  'collection_share_count',
                ).replaceAll('{count}', '$bookCount'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (languages.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  TranslationService.translate(
                    context,
                    'collection_share_languages',
                  ).replaceAll('{languages}', languages.join(', ')),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                          context,
                          'collection_share_explainer',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'collection_share_copy',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'collection_share_send',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [CollectionShareSheet] as a modal bottom sheet.
Future<void> showCollectionShareSheet(
  BuildContext context, {
  required String collectionName,
  required int bookCount,
  required String yaml,
  required VoidCallback onShare,
  List<String> languages = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => CollectionShareSheet(
      collectionName: collectionName,
      bookCount: bookCount,
      yaml: yaml,
      languages: languages,
      onShare: onShare,
    ),
  );
}
