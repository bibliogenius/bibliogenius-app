import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../services/translation_service.dart';
import '../widgets/app_snack_bar.dart';

/// The "Not interested" gesture, shared by every recommendation surface
/// (dashboard digest, "See all" screen, similar-books carousel): dismiss
/// [bookId] through [RecommendationProvider] and show the SnackBar with its
/// immediate Undo, so wording and behaviour never drift between surfaces.
void dismissRecommendationWithUndo(BuildContext context, String bookId) {
  final provider = context.read<RecommendationProvider>();
  provider.dismiss(bookId);
  _showDismissUndoSnackBar(context, () => provider.restoreDismissed(bookId));
}

/// Same gesture for an EXTERNAL discovery card (ADR-060 section 4.5):
/// keyed by the namespaced [externalKey] through the second store, same
/// SnackBar and Undo so both card kinds feel identical.
void dismissExternalSuggestionWithUndo(BuildContext context, String externalKey) {
  final provider = context.read<RecommendationProvider>();
  provider.dismissExternal(externalKey);
  _showDismissUndoSnackBar(
    context,
    () => provider.restoreDismissedExternal(externalKey),
  );
}

void _showDismissUndoSnackBar(BuildContext context, VoidCallback onUndo) {
  AppSnackBar.info(
    context,
    TranslationService.translate(context, 'recommendation_dismissed'),
    action: SnackBarAction(
      label: TranslationService.translate(context, 'action_undo'),
      onPressed: onUndo,
    ),
  );
}

/// Badge label for a suggestion source (Dart-only field, ADR-060). Only
/// external cards carry a badge; library cards return null and render
/// unchanged.
String? recommendationSourceBadgeLabel(BuildContext context, String source) {
  if (source != RecommendationSource.external) return null;
  return TranslationService.translate(context, 'suggestion_badge_external');
}

/// Translate one recommendation reason into a display line.
///
/// The wire keys come from the Rust engine and map 1:1 to i18n keys
/// (`same_author` -> `reason_same_author`). Unknown keys (an older Flutter
/// build against a newer engine) degrade to the raw value rather than
/// showing an untranslated key.
String recommendationReasonLabel(
  BuildContext context,
  RecommendationReason reason,
) {
  const knownTypes = {
    'same_author',
    'shared_subject',
    'same_publisher',
    'close_period',
    'highly_rated',
    'in_reading_pile',
    'series_missing_volume',
    'author_completion',
  };
  if (!knownTypes.contains(reason.type)) return reason.value;
  return TranslationService.translate(
    context,
    'reason_${reason.type}',
    // Client-built reasons (external cards) may carry several
    // placeholders; wire reasons keep the {value} convention.
    params: reason.params ?? {'value': reason.value},
  );
}

/// True when the reason payload is already printed next to the chip: every
/// recommendation surface shows the author line, so "Same author: X" repeats X
/// one line below itself.
bool recommendationReasonRepeatsCard(RecommendationReason reason) =>
    reason.type == 'same_author';

/// True when the reason value already reads as a label on its own (a shelf or
/// genre tag): "Shared subject: Crime fiction" says nothing "Crime fiction"
/// next to the tag icon does not.
bool recommendationReasonIsSelfDescribing(RecommendationReason reason) =>
    reason.type == 'shared_subject';

/// Label printed on a reason chip. The author reason drops its value (already
/// on the card), a self-describing value drops its sentence prefix (carried by
/// the icon), [compact] drops the prefix of every reason for the narrow
/// carousel cards, and the rest spells the full sentence.
String recommendationReasonChipLabel(
  BuildContext context,
  RecommendationReason reason, {
  bool compact = false,
}) {
  if (recommendationReasonRepeatsCard(reason)) {
    return TranslationService.translate(context, 'reason_same_author_short');
  }
  if (compact || recommendationReasonIsSelfDescribing(reason)) {
    return reason.value;
  }
  return recommendationReasonLabel(context, reason);
}

/// Sentence announced to a screen reader. Always the full wording -- a chip
/// trimmed for the eye still has to be understandable on its own -- minus the
/// author echo, which the card already speaks one line above.
String recommendationReasonSpokenLabel(
  BuildContext context,
  RecommendationReason reason,
) {
  if (recommendationReasonRepeatsCard(reason)) {
    return TranslationService.translate(context, 'reason_same_author_short');
  }
  return recommendationReasonLabel(context, reason);
}

/// Icon standing for a reason type, used to prefix the reason chips. Keeps the
/// visual vocabulary of "why this book" aligned with the wire keys above;
/// unknown keys fall back to a neutral tag.
IconData recommendationReasonIcon(RecommendationReason reason) {
  switch (reason.type) {
    case 'same_author':
      return Icons.person_outline;
    case 'shared_subject':
      return Icons.local_offer_outlined;
    case 'same_publisher':
      return Icons.apartment_outlined;
    case 'close_period':
      return Icons.schedule_outlined;
    case 'highly_rated':
      return Icons.star_outline;
    case 'in_reading_pile':
      return Icons.bookmark_outline;
    case 'series_missing_volume':
      return Icons.collections_bookmark_outlined;
    case 'author_completion':
      return Icons.person_search_outlined;
    default:
      return Icons.label_outline;
  }
}
