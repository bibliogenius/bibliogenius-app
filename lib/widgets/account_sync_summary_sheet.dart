import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';

/// Emphasized primary action for the account-sync surfaces: comfortable
/// height, bold label, medium radius (matches the sync-screen mockup instead
/// of the default theme pill). Shared by the account screen and the
/// springboard summary sheet.
ButtonStyle accountSyncPrimaryActionStyle(BuildContext context) {
  return FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 16),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
    ),
  );
}

/// Secondary action: clearly visible primary border on a surface background,
/// same metrics as the primary action so the two read as one button stack.
ButtonStyle accountSyncSecondaryActionStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 16),
    foregroundColor: cs.primary,
    backgroundColor: cs.surface,
    side: BorderSide(color: cs.primary, width: 1.5),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
    ),
  );
}

/// Springboard "read on my other devices" popin: a state-aware summary of the
/// encrypted account, not full management. Signed out it offers create / join
/// / pair (the same doors as the hub screen); signed in it shows the account,
/// the device count, a direct sync action and the door to the management
/// screen. Heavy flows (signup, pairing, device removal) stay full screens.
Future<void> showAccountSyncSummarySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDesign.spacingMd,
            0,
            AppDesign.spacingMd,
            AppDesign.spacingMd + media.viewInsets.bottom,
          ),
          child: const AccountSyncSummaryBody(),
        ),
      );
    },
  );
}

/// State-aware account summary used inside bottom sheets: the springboard
/// popin above, and the backup popin (which swaps its content to this body
/// when the "Compte chiffré" tile is tapped). The header adapts to the host:
/// goal phrasing by default, account title when embedded elsewhere.
class AccountSyncSummaryBody extends StatefulWidget {
  final String titleKey;
  final IconData icon;

  const AccountSyncSummaryBody({
    super.key,
    this.titleKey = 'settings_goal_sync_devices',
    this.icon = Icons.devices,
  });

  @override
  State<AccountSyncSummaryBody> createState() => _AccountSyncSummaryBodyState();
}

class _AccountSyncSummaryBodyState extends State<AccountSyncSummaryBody> {
  late final AccountSyncProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<AccountSyncProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await _provider.refreshStatus();
    if (!mounted) return;
    if (_provider.signedIn) await _provider.refreshDevices();
  }

  String _t(String key, {Map<String, String>? params}) =>
      TranslationService.translate(context, key, params: params);

  /// Closes the sheet, then navigates. Capturing the router first keeps the
  /// push safe after this subtree is disposed by the pop.
  void _popThenPush(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(location);
  }

  Future<void> _syncNow() async {
    final key = await _provider.syncNowMessageKey();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t(key))));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AccountSyncProvider>(
      builder: (context, p, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppDesign.spacingSm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      _t(widget.titleKey),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesign.spacingMd),
            if (p.signedIn) ..._signedIn(context, p) else ..._signedOut(),
          ],
        );
      },
    );
  }

  List<Widget> _signedIn(BuildContext context, AccountSyncProvider p) {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_user),
        title: Text(_t('account_sync_signed_in_label')),
        subtitle: Text(
          p.status.email,
          style: const TextStyle(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Text(
        _t(
          'account_sync_devices_count',
          params: {'count': '${p.devices.length}'},
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: AppDesign.spacingLg),
      FilledButton.icon(
        icon: const Icon(Icons.sync),
        onPressed: p.busy ? null : _syncNow,
        label: Text(_t('account_sync_sync_now')),
        style: accountSyncPrimaryActionStyle(context),
      ),
      const SizedBox(height: AppDesign.spacingSm),
      OutlinedButton.icon(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => _popThenPush('/account-sync'),
        label: Text(_t('account_sync_manage_button')),
        style: accountSyncSecondaryActionStyle(context),
      ),
    ];
  }

  List<Widget> _signedOut() {
    return [
      Text(
        _t('account_sync_signed_out_intro'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: AppDesign.spacingLg),
      FilledButton.icon(
        icon: const Icon(Icons.person_add_alt_1),
        onPressed: () => _popThenPush('/account-sync/create'),
        label: Text(_t('account_sync_create_account')),
        style: accountSyncPrimaryActionStyle(context),
      ),
      const SizedBox(height: AppDesign.spacingSm),
      OutlinedButton.icon(
        icon: const Icon(Icons.login),
        onPressed: () => _popThenPush('/account-sync/join'),
        label: Text(_t('account_sync_join_account')),
        style: accountSyncSecondaryActionStyle(context),
      ),
      const SizedBox(height: AppDesign.spacingSm),
      TextButton.icon(
        icon: const Icon(Icons.qr_code_scanner),
        onPressed: () => _popThenPush('/account-sync/pair'),
        label: Text(_t('account_sync_pair_cta')),
      ),
    ];
  }
}
