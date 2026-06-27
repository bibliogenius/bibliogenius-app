import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';

/// Hub for the multi-device account sync feature.
///
/// Signed out: explains the feature and offers create / join. Signed in: shows
/// the account email, the authorized device list, and add-device / sign-out
/// actions. Data convergence between devices is not active yet; the
/// screen says so honestly rather than implying a sync that does not run.
class AccountSyncScreen extends StatefulWidget {
  const AccountSyncScreen({super.key});

  @override
  State<AccountSyncScreen> createState() => _AccountSyncScreenState();
}

class _AccountSyncScreenState extends State<AccountSyncScreen> {
  late final AccountSyncProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<AccountSyncProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await _provider.refreshStatus();
    if (!mounted) return;
    if (_provider.signedIn) await _provider.refreshDevices();
  }

  String _t(String key) => TranslationService.translate(context, key);

  Future<void> _openAndReload(String location) async {
    await context.push<void>(location);
    if (!mounted) return;
    await _load();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('account_sync_logout_confirm_title')),
        content: Text(_t('account_sync_logout_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('account_sync_logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _provider.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: _t('account_sync_title'),
        actions: [
          Consumer<AccountSyncProvider>(
            builder: (context, p, _) => p.signedIn
                ? IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: _t('retry'),
                    onPressed: p.busy ? null : _load,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.watch<ThemeProvider>().themeStyle,
          ),
        ),
        child: SafeArea(
          child: Consumer<AccountSyncProvider>(
            builder: (context, p, _) {
              return RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  child: p.signedIn
                      ? _SignedInView(
                          provider: p,
                          onAddDevice: () =>
                              _openAndReload('/account-sync/add-device'),
                          onLogout: _confirmLogout,
                        )
                      : _SignedOutView(
                          onCreate: () =>
                              _openAndReload('/account-sync/create'),
                          onJoin: () => _openAndReload('/account-sync/join'),
                          onPair: () => _openAndReload('/account-sync/pair'),
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shared section header with the screen-reader header role.
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppDesign.spacingLg,
          bottom: AppDesign.spacingSm,
        ),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// Honest banner: management works now, automatic convergence is not live yet.
class _PendingNote extends StatelessWidget {
  const _PendingNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              TranslationService.translate(context, 'account_sync_pending_note'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onPair;
  const _SignedOutView({
    required this.onCreate,
    required this.onJoin,
    required this.onPair,
  });

  String _t(BuildContext c, String k) => TranslationService.translate(c, k);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(context, 'account_sync_signed_out_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingLg),
        FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: onCreate,
          label: Text(_t(context, 'account_sync_create_account')),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.login),
          onPressed: onJoin,
          label: Text(_t(context, 'account_sync_join_account')),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: onPair,
          label: Text(_t(context, 'account_sync_pair_cta')),
        ),
        const SizedBox(height: AppDesign.spacingLg),
        const _PendingNote(),
      ],
    );
  }
}

class _SignedInView extends StatelessWidget {
  final AccountSyncProvider provider;
  final VoidCallback onAddDevice;
  final VoidCallback onLogout;
  const _SignedInView({
    required this.provider,
    required this.onAddDevice,
    required this.onLogout,
  });

  String _t(BuildContext c, String k) => TranslationService.translate(c, k);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user, color: cs.primary),
            const SizedBox(width: AppDesign.spacingSm),
            Expanded(
              child: Text(
                TranslationService.translate(
                  context,
                  'account_sync_signed_in_as',
                  params: {'email': provider.status.email},
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesign.spacingMd),
        const _PendingNote(),
        _SectionHeader(_t(context, 'account_sync_devices_title')),
        if (provider.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesign.spacingSm,
            ),
            child: Text(
              _t(context, 'account_sync_no_devices'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          ...provider.devices.map((d) => _DeviceTile(device: d)),
        const SizedBox(height: AppDesign.spacingLg),
        FilledButton.icon(
          icon: const Icon(Icons.add_to_queue),
          onPressed: onAddDevice,
          label: Text(_t(context, 'account_sync_add_device')),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          onPressed: provider.busy ? null : onLogout,
          label: Text(_t(context, 'account_sync_logout')),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final AccountDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selfLabel = TranslationService.translate(
      context,
      'account_sync_this_device',
    );
    return Semantics(
      label: device.isSelf ? '${device.name}, $selfLabel' : device.name,
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: AppDesign.spacingXs),
        child: ListTile(
          leading: Icon(
            device.isSelf ? Icons.smartphone : Icons.devices_other,
            color: cs.primary,
          ),
          title: Text(device.name),
          trailing: device.isSelf
              ? Chip(
                  label: Text(selfLabel),
                  visualDensity: VisualDensity.compact,
                )
              : null,
        ),
      ),
    );
  }
}
