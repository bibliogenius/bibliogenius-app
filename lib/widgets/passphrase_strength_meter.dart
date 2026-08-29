import 'package:flutter/material.dart';

import '../providers/account_sync_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';

/// Live passphrase strength meter: a 0..4 bar plus the textual label, warning,
/// and suggestions. The value is also exposed to screen readers (color alone
/// must not convey the strength, A1).
///
/// Shared by every surface that asks the reader to invent a secret: account
/// creation (where `acceptable` is the hard gate) and the manual full-backup
/// export (where the meter is advisory and only a length floor blocks).
class PassphraseStrengthMeter extends StatelessWidget {
  final PassphraseStrength strength;

  const PassphraseStrengthMeter({super.key, required this.strength});

  /// The backend returns stable slugs (`zxcvbn_warning_*`,
  /// `zxcvbn_suggestion_*`), never English prose, so the advice can be shown in
  /// the reader's language. `TranslationService.translate` echoes the key back
  /// when no catalogue has it, so an unknown slug (a zxcvbn variant added
  /// upstream before its `.po` entries land) resolves to itself and is dropped
  /// rather than displayed raw.
  static String? _localize(BuildContext context, String slug) {
    final text = TranslationService.translate(context, slug);
    return text == slug ? null : text;
  }

  static List<String> _localizeAll(BuildContext context, List<String> slugs) {
    final out = <String>[];
    for (final slug in slugs) {
      final text = _localize(context, slug);
      if (text != null) out.add(text);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = TranslationService.translate(
      context,
      'account_sync_strength_${strength.score}',
    );
    // Theme colors only (vetted contrast); the text label carries the meaning.
    final Color barColor = strength.score < 2
        ? cs.error
        : strength.score == 2
        ? cs.tertiary
        : cs.primary;
    final meterLabel = TranslationService.translate(
      context,
      'account_sync_strength_label',
    );
    final warning = strength.warning == null
        ? null
        : _localize(context, strength.warning!);
    final suggestions = _localizeAll(context, strength.suggestions);
    // Fold the warning and actionable suggestions into the spoken label so a
    // screen-reader user gets the same guidance as a sighted one (A1). The meter
    // is a live region so the score is re-announced as the passphrase is typed.
    final semanticParts = <String>[
      '$meterLabel: $label',
      if (warning != null) warning,
      ...suggestions,
    ];

    return Semantics(
      label: semanticParts.join('. '),
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            child: LinearProgressIndicator(
              value: strength.length == 0 ? 0 : (strength.score + 1) / 5,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              color: barColor,
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            '$meterLabel: $label',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (warning != null) ...[
            const SizedBox(height: AppDesign.spacingXs),
            Text(
              warning,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingXs),
            Text(
              suggestions.join('\n'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
