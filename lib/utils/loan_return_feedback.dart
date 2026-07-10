/// Feedback shown after a borrower-initiated return.
///
/// The backend removes the local copy whether or not it managed to tell the
/// lender, so the two outcomes are indistinguishable from the HTTP status. When
/// the lender was not reached the book stays out on loan on their side, and the
/// user is the only one who can close it: saying "returned successfully" there
/// costs them the one moment they could have acted.
library;

import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Foreground of both pills, pinned rather than inherited.
///
/// Material 3 draws SnackBar content in `colorScheme.onInverseSurface`, which
/// flips with the theme: on a fixed background that yields dark text on orange in
/// the dark theme, around 3.3:1. Fixing both ends keeps the pair deterministic.
const _onFeedback = Colors.white;

/// Backgrounds chosen for contrast against [_onFeedback], not for hue alone.
/// White on `Colors.green` is 2.8:1 and on `Colors.orange.shade900` 3.8:1; both
/// fail WCAG 2.1 AA for normal text. These clear it: 5.1:1 and 5.6:1.
const _successBackground = Color(0xFF2E7D32); // green.shade800
const _warningBackground = Color(0xFFBF360C); // deepOrange.shade900

/// The SnackBar for a return whose lender notification either landed or did not.
///
/// The failed case is deliberately slower to dismiss: it asks the user to do
/// something, where the success case only confirms.
SnackBar returnOutcomeSnackBar(BuildContext context, bool lenderNotified) {
  if (lenderNotified) {
    return SnackBar(
      content: Text(
        TranslationService.translate(context, 'book_returned_success'),
        style: const TextStyle(color: _onFeedback),
      ),
      backgroundColor: _successBackground,
    );
  }

  return SnackBar(
    content: Text(
      TranslationService.translate(
        context,
        'book_returned_lender_not_notified',
      ),
      style: const TextStyle(color: _onFeedback),
    ),
    backgroundColor: _warningBackground,
    duration: const Duration(seconds: 8),
  );
}
