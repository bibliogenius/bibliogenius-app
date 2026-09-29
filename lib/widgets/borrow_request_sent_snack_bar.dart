import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';
import 'app_snack_bar.dart';
import 'contact_card_prompt.dart';

/// Matches the Flutter default the plain confirmation used to get.
const _plainDuration = Duration(seconds: 4);

/// Longer: a second sentence and an action to reach.
const _inviteDuration = Duration(seconds: 8);

/// Confirms that a borrow request left, shared by every screen that sends one.
///
/// When the card is empty and the lender is a paired peer, the confirmation
/// also asks for it: the lender is about to need a way to reach the borrower
/// to agree on the loan (ADR-067 D9). A lender that is not a paired peer only
/// receives the card under conditions this screen cannot see, so it gets the
/// plain confirmation rather than a promise that may not hold.
void showBorrowRequestSentSnackBar(
  BuildContext context, {
  String? lenderName,
  required bool lenderIsPairedPeer,
}) {
  String t(String key) => TranslationService.translate(context, key);
  final sent = lenderName == null
      ? t('borrow_request_sent')
      : '${t('request_sent_to')} $lenderName';

  final invite =
      lenderIsPairedPeer &&
      context.read<HubDirectoryProvider>().shouldInviteContactCard;
  if (!invite) {
    AppSnackBar.success(context, sent, duration: _plainDuration);
    return;
  }

  // The calling screen or sheet may be gone by the time the action is
  // tapped (the directory sheet pops right after sending), so the form opens
  // from the root navigator, which outlives both.
  final navigatorContext = Navigator.of(context, rootNavigator: true).context;
  AppSnackBar.success(
    context,
    '$sent ${t('borrow_request_sent_contact_hint')}',
    duration: _inviteDuration,
    // An action would otherwise pin the bar until tapped, and it would follow
    // the reader from screen to screen (see AppSnackBar). Except under a
    // screen reader: Flutter's timer only reads `persist`, and an expiring bar
    // would vanish before focus can reach its action.
    persist: MediaQuery.accessibleNavigationOf(context),
    action: SnackBarAction(
      label: t('add'),
      onPressed: () => showContactCardSheet(navigatorContext),
    ),
  );
}
