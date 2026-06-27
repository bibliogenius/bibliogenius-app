import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/translation_service.dart';
import '../theme/app_design.dart';

/// Read-only display of a 24-word BIP39 recovery phrase as a numbered grid, with
/// a copy action. Shown ONCE right after signup (the phrase is never stored and
/// cannot be shown again). The whole grid is exposed to screen readers as the
/// ordered phrase so it can be transcribed.
class RecoveryPhraseView extends StatelessWidget {
  final String phrase;
  const RecoveryPhraseView({super.key, required this.phrase});

  List<String> get _words =>
      phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  String _t(BuildContext c, String k) => TranslationService.translate(c, k);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final words = _words;
    // Screen-reader rendering: "1. abandon, 2. ability, ..." so the order is
    // unambiguous when transcribing by ear.
    final spoken = [
      for (var i = 0; i < words.length; i++) '${i + 1}. ${words[i]}',
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            ),
            child: Wrap(
              spacing: AppDesign.spacingSm,
              runSpacing: AppDesign.spacingSm,
              children: [
                for (var i = 0; i < words.length; i++)
                  _WordCell(index: i + 1, word: words[i]),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(_t(context, 'account_sync_recovery_copy')),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: phrase));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_t(context, 'account_sync_recovery_copied')),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A single "n. word" cell in the recovery grid. Monospace for legibility.
class _WordCell extends StatelessWidget {
  final int index;
  final String word;
  const _WordCell({required this.index, required this.word});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingSm,
        vertical: AppDesign.spacingXs,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              word,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
