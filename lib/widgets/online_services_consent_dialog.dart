import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';

/// Asks the question of ADR-073 D2 before a network action of the user:
/// may this device be registered on the hub?
///
/// Returns true when the action may go on: the installation already
/// consents (nothing is shown), or the user just accepted the dialog (the
/// yes is then written, here and nowhere else). Returns false when the
/// user refused or dismissed it: the caller drops the action, records
/// nothing and registers nothing. (The suggestion lookups of ADR-060 and
/// ADR-061 are outside this consent and still reach the hub: no text of
/// the dialog may promise that nothing at all is sent.)
///
/// One dialog, the same text at every entry point. [publishingWithoutApproval]
/// only changes the line about the list of books, for the one action that
/// makes it readable by everyone: publishing a library that does not ask
/// for an approval.
Future<bool> confirmOnlineServices(
  BuildContext context, {
  bool publishingWithoutApproval = false,
}) async {
  final answer = await _askOnlineServices(
    context,
    publishingWithoutApproval: publishingWithoutApproval,
    localOnlyOffered: false,
  );
  return answer == true;
}

/// How a pairing may go on after the question of ADR-073 D2.
enum PairingConsent {
  /// The installation consents: the hub may be used.
  online,

  /// The user declined the registration and the peer has an address on
  /// the local network: the pairing goes on there. This device is not
  /// registered, and the Rust core keeps its hub gate closed: the peer's
  /// relay credentials may be stored, but nothing is deposited or read on
  /// the hub because of this pairing until the user agrees to register.
  localOnly,

  /// The dialog was dismissed, or declined with no local address to fall
  /// back on: the pairing is dropped.
  cancelled,
}

/// The question, for a pairing. The local network was designed to work
/// without any server: when [localAddress] says the peer can be reached
/// there, declining the registration does not drop the pairing. The
/// dialog then offers "continue without the server" instead of "refuse
/// and cancel". Dismissing it still cancels.
Future<PairingConsent> confirmOnlineServicesForPairing(
  BuildContext context, {
  required bool localAddress,
}) async {
  final answer = await _askOnlineServices(
    context,
    publishingWithoutApproval: false,
    localOnlyOffered: localAddress,
  );
  if (answer == true) return PairingConsent.online;
  if (answer == false && localAddress) return PairingConsent.localOnly;
  return PairingConsent.cancelled;
}

/// True: consents (already, or just accepted). False: declined with the
/// button. Null: dismissed.
Future<bool?> _askOnlineServices(
  BuildContext context, {
  required bool publishingWithoutApproval,
  required bool localOnlyOffered,
}) async {
  final hub = context.read<HubDirectoryProvider>();
  if (await hub.onlineServicesAllowed()) return true;
  // "Could not read the device" is not a no. Read once more before asking:
  // someone who consents by use must not be handed a question whose yes
  // would be written down for good.
  if (hub.onlineServicesUnreadable) {
    await Future<void>.delayed(_unreadableRetryDelay);
    if (await hub.onlineServicesAllowed()) return true;
  }
  if (!context.mounted) return null;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => OnlineServicesConsentDialog(
      publishingWithoutApproval: publishingWithoutApproval,
      localOnlyOffered: localOnlyOffered,
    ),
  );
  if (accepted != true) return accepted;
  await hub.recordOnlineServicesGrant();
  return true;
}

/// The page of the public site that says who runs the hub and how to have
/// a registration deleted. The app cannot withdraw a consent yet, so the
/// dialog points there. The page exists in French (at the root), English,
/// Spanish and German; any other language gets the English one.
Uri dataDeletionPageUri(String languageCode) {
  const translated = {'en', 'es', 'de'};
  final folder = languageCode == 'fr'
      ? ''
      : '${translated.contains(languageCode) ? languageCode : 'en'}/';
  return Uri.parse('https://bibliogenius.org/${folder}data-deletion.html');
}

/// How long to wait before reading again a device that could not be read.
const _unreadableRetryDelay = Duration(milliseconds: 400);

/// For a screen whose whole purpose needs the hub (creating or joining an
/// encrypted account): asks as the screen opens, before anything is typed,
/// and leaves the screen on a refusal.
Future<void> confirmOnlineServicesOrLeave(BuildContext context) async {
  if (await confirmOnlineServices(context)) return;
  if (context.mounted) await Navigator.of(context).maybePop();
}

/// Shows what a registered device sends to the hub, with nothing to
/// answer: the notice for installations whose consent is inferred from
/// their use of the network (ADR-073 D3).
Future<void> showOnlineServicesInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const OnlineServicesConsentDialog.info(),
  );
}

/// Key of the one-time notice shown to installations whose consent is
/// inferred (ADR-073 D3). Also the prefix of its dismissal preference.
const kOnlineServicesNoticeFlashKey = 'flash_online_services_notice';

/// What the notice banner says: this device is registered, why, and a way
/// to read what it sends. Nothing to answer; the banner's own close button
/// dismisses it for good.
class OnlineServicesNotice extends StatelessWidget {
  const OnlineServicesNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String t(String key) => TranslationService.translate(context, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t('online_reg_notice_title'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t('online_reg_notice_body'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => showOnlineServicesInfo(context),
          icon: const Icon(Icons.list_alt_outlined, size: 18),
          label: Text(t('online_reg_notice_action')),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

/// The dialog itself. The text scrolls when it does not fit (large text
/// sizes), the buttons stay in view under it.
class OnlineServicesConsentDialog extends StatefulWidget {
  const OnlineServicesConsentDialog({
    super.key,
    this.publishingWithoutApproval = false,
    this.localOnlyOffered = false,
  }) : asksForConsent = true;

  /// Read-only: same list, details open, a single button to close.
  const OnlineServicesConsentDialog.info({super.key})
    : asksForConsent = false,
      publishingWithoutApproval = false,
      localOnlyOffered = false;

  final bool asksForConsent;
  final bool publishingWithoutApproval;

  /// The action can go on over the local network without the hub: the
  /// declining button says so instead of cancelling.
  final bool localOnlyOffered;

  @override
  State<OnlineServicesConsentDialog> createState() =>
      _OnlineServicesConsentDialogState();
}

class _OnlineServicesConsentDialogState
    extends State<OnlineServicesConsentDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final theme = Theme.of(context);
    final asks = widget.asksForConsent;
    final actions = asks
        ? [
            // Two buttons of the same weight: neither answer is pushed.
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                t(
                  widget.localOnlyOffered
                      ? 'online_reg_continue_local'
                      : 'online_reg_refuse',
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t('online_reg_accept')),
            ),
          ]
        : [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('close')),
            ),
          ];
    // Not an AlertDialog: its title stays fixed above the text, and at a
    // large text size on a small phone the title and the buttons alone
    // exceed the screen. Here the title scrolls with the text, and only
    // the buttons stay in view.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          namesRoute: true,
                          header: true,
                          child: Text(
                            t(
                              asks
                                  ? 'online_reg_title'
                                  : 'online_reg_info_title',
                            ),
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _OnlineServicesSummary(
                          asksForConsent: asks,
                          publishingWithoutApproval:
                              widget.publishingWithoutApproval,
                          localOnlyOffered: widget.localOnlyOffered,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the hub receives, item by item, then the explanations behind
/// "Details".
class _OnlineServicesSummary extends StatelessWidget {
  const _OnlineServicesSummary({
    required this.asksForConsent,
    required this.publishingWithoutApproval,
    required this.localOnlyOffered,
  });

  final bool asksForConsent;
  final bool publishingWithoutApproval;
  final bool localOnlyOffered;

  /// The explanations, as (title key, body key).
  static const _details = [
    ('online_reg_d_three_title', 'online_reg_d_three_body'),
    ('online_reg_d_books_title', 'online_reg_d_books_body'),
    ('online_reg_d_device_id_title', 'online_reg_d_device_id_body'),
    ('online_reg_d_device_model_title', 'online_reg_d_device_model_body'),
    ('online_reg_d_mailbox_title', 'online_reg_d_mailbox_body'),
    ('online_reg_d_last_seen_title', 'online_reg_d_last_seen_body'),
    ('online_reg_d_no_ads_title', 'online_reg_d_no_ads_body'),
    ('online_reg_d_without_title', 'online_reg_d_without_body'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    String t(String key) => TranslationService.translate(
      context,
      key,
      // The switch is named as the settings name it, in every language.
      params: {
        'toggle': TranslationService.translate(
          context,
          'hub_coming_soon_toggle',
        ),
      },
    );

    final items = [
      publishingWithoutApproval
          ? 'online_reg_item_books_public'
          : 'online_reg_item_books',
      'online_reg_item_covers',
      'online_reg_item_library',
      'online_reg_item_device_id',
      'online_reg_item_device_model',
      'online_reg_item_messages',
      'online_reg_item_last_seen',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (asksForConsent) ...[
          Text(t('online_reg_intro'), style: body),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(t('online_reg_received'), style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        for (final key in items) _Bullet(text: t(key), style: body),
        if (asksForConsent) ...[
          const SizedBox(height: 12),
          Text(
            t(
              localOnlyOffered
                  ? 'online_reg_refusal_local'
                  : 'online_reg_refusal',
            ),
            style: body,
          ),
        ],
        const SizedBox(height: 4),
        Theme(
          // No divider lines around the expansion tile inside a dialog.
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: !asksForConsent,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(t('online_reg_details'), style: theme.textTheme.titleSmall),
            children: [
              for (final (title, text) in _details) ...[
                Semantics(
                  header: true,
                  child: Text(t(title), style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 2),
                Text(t(text), style: body),
                const SizedBox(height: 12),
              ],
              Semantics(
                header: true,
                child: Text(
                  t('online_reg_d_who_title'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 2),
              Text(t('online_reg_d_who_body'), style: body),
              TextButton.icon(
                onPressed: () async {
                  final page = dataDeletionPageUri(
                    Provider.of<ThemeProvider>(
                      context,
                      listen: false,
                    ).locale.languageCode,
                  );
                  // No browser, or a platform that refuses the link: the
                  // dialog stays usable, the page is named in its text.
                  try {
                    await launchUrl(
                      page,
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (e) {
                    debugPrint('Consent dialog: could not open $page: $e');
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(t('online_reg_d_who_link')),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text('•  ', style: style)),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
