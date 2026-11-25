import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import 'online_services_consent_dialog.dart';

/// Whether this device is registered on the hub, and the way out
/// (ADR-073 D4): the settings row that says it, with the "unregister"
/// action when there is a registration to withdraw.
class HubRegistrationCard extends StatefulWidget {
  const HubRegistrationCard({super.key});

  @override
  State<HubRegistrationCard> createState() => _HubRegistrationCardState();
}

class _HubRegistrationCardState extends State<HubRegistrationCard> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // The row may be the first thing to ask on this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HubDirectoryProvider>().onlineServicesAllowed();
    });
  }

  Future<void> _openDataDeletionPage() async {
    final page = dataDeletionPageUri(
      context.read<ThemeProvider>().locale.languageCode,
    );
    // No browser, or a platform that refuses the link: the row stays
    // usable, the page is named in its text.
    try {
      await launchUrl(page, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Registration row: could not open $page: $e');
    }
  }

  Future<void> _unregister() async {
    final hub = context.read<HubDirectoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    String t(String key) => TranslationService.translate(context, key);
    final messages = {
      HubWithdrawal.done: t('hub_unreg_done'),
      HubWithdrawal.pending: t('hub_unreg_pending'),
      HubWithdrawal.unconfirmed: t('hub_unreg_unconfirmed'),
      HubWithdrawal.failed: t('hub_unreg_failed'),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmUnregisterDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final HubWithdrawal result;
    try {
      result = await hub.withdrawOnlineServices();
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    if (result == HubWithdrawal.accountSignedIn) {
      await showDialog<void>(
        context: context,
        builder: (_) => const _SignedInDialog(),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(messages[result]!)));
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final (registered, pending, unconfirmed) = context
        .select<HubDirectoryProvider, (bool, bool, bool)>(
          (hub) => (
            hub.onlineServicesKnownAllowed,
            hub.hubRemovalPending,
            hub.hubRemovalUnconfirmed,
          ),
        );
    final state = pending
        ? 'hub_unreg_state_pending'
        : unconfirmed && !registered
        ? 'hub_unreg_state_unconfirmed'
        : registered
        ? 'hub_unreg_state_registered'
        : 'hub_unreg_state_not_registered';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              registered ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            ),
            title: Text(t('hub_unreg_title')),
            // Announced when it changes, for a screen reader user who just
            // confirmed the dialog.
            subtitle: Semantics(liveRegion: true, child: Text(t(state))),
          ),
          if (unconfirmed && !registered) ...[
            const Divider(height: 1),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                // The page of the site that says how to ask for a deletion.
                child: TextButton.icon(
                  onPressed: _openDataDeletionPage,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(t('online_reg_d_who_link')),
                ),
              ),
            ),
          ],
          if (registered) ...[
            const Divider(height: 1),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: TextButton.icon(
                  onPressed: _working ? null : _unregister,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: ExcludeSemantics(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.logout, size: 18),
                  label: Text(t('hub_unreg_action')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Says what the hub deletes, what the contacts lose, what keeps working,
/// and what does not come back. Can be cancelled.
class _ConfirmUnregisterDialog extends StatelessWidget {
  const _ConfirmUnregisterDialog();

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    return AlertDialog(
      scrollable: true,
      title: Text(t('hub_unreg_confirm_title')),
      content: Text(t('hub_unreg_confirm_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t('cancel')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t('hub_unreg_confirm_action')),
        ),
      ],
    );
  }
}

/// The encrypted account goes through the hub: the user signs out of it
/// first. Nothing was withdrawn.
class _SignedInDialog extends StatelessWidget {
  const _SignedInDialog();

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    return AlertDialog(
      scrollable: true,
      content: Text(t('hub_unreg_account_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
        FilledButton.tonal(
          onPressed: () {
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.push('/account-sync');
          },
          child: Text(t('hub_unreg_account_action')),
        ),
      ],
    );
  }
}
