import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/account_sync_summary_sheet.dart';
import '../widgets/genie_app_bar.dart';

/// Hub for the multi-device account sync feature.
///
/// Signed out: explains the feature and offers create / join. Signed in: shows
/// the account email, the authorized device list, and add-device / sign-out
/// actions.
///
/// Both the "Compte chiffré" and "Partager l'accès" settings entries land
/// here (one account screen, no separate share flow). [shareIntent] carries
/// which entry was tapped so the title and the contextual note acknowledge
/// the share intent instead of silently showing the same screen.
/// Desktop: cap the content column so the cards and the action-button stack
/// keep a hand-friendly width instead of stretching across the window.
/// Narrower than [AppDesign.maxContentWidth] (900, meant for long settings
/// lists): this screen is a short action stack, closer to an auth form.
const double _maxBodyWidth = 560.0;

class AccountSyncScreen extends StatefulWidget {
  final bool shareIntent;

  const AccountSyncScreen({super.key, this.shareIntent = false});

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

  /// Confirm and remove another device from the account (soft revocation). The
  /// copy is deliberately honest: the device stops syncing but keeps the data it
  /// already downloaded (it is not a security lock — see the removal note).
  Future<void> _confirmRemoveDevice(AccountDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('account_sync_remove_device_confirm_title')),
        content: Text(
          TranslationService.translate(
            ctx,
            'account_sync_remove_device_confirm_body',
            params: {'name': device.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('account_sync_remove_device_button')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _provider.removeDevice(device.deviceId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('account_sync_remove_device_error'))),
      );
    }
  }

  /// Manually trigger one sync cycle and show a human confirmation. The
  /// JSON-to-message mapping lives in the provider (shared with the
  /// springboard summary sheet).
  Future<void> _syncNow() async {
    final key = await _provider.syncNowMessageKey();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t(key))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        // The share title has a dedicated SHORT form: GenieAppBar hides the
        // whole title block (title + library subtitle) when the measured
        // title cannot fit next to the action buttons, and the full tile
        // label ("Partager l'accès à ma bibliothèque") never fits.
        title: _t(
          widget.shareIntent
              ? 'account_share_access_short_title'
              : 'account_sync_title',
        ),
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
        // Expand: the Scaffold gives its body loose constraints, so without
        // this the gradient container shrink-wraps the (short) content and
        // the plain scaffold background shows below it on tall windows.
        constraints: const BoxConstraints.expand(),
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxBodyWidth,
                      ),
                      child: p.signedIn
                          ? _SignedInView(
                              provider: p,
                              shareIntent: widget.shareIntent,
                              onAddDevice: () =>
                                  _openAndReload('/account-sync/add-device'),
                              onLogout: _confirmLogout,
                              onSyncNow: _syncNow,
                              onRemoveDevice: _confirmRemoveDevice,
                            )
                          : _SignedOutView(
                              shareIntent: widget.shareIntent,
                              onCreate: () =>
                                  _openAndReload('/account-sync/create'),
                              onJoin: () =>
                                  _openAndReload('/account-sync/join'),
                              onPair: () =>
                                  _openAndReload('/account-sync/pair'),
                            ),
                    ),
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
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// Contextual caption in a primary-tinted banner. The text follows the entry
/// point: account benefits by default, join-with-passphrase guidance when the
/// user came through "Partager l'accès".
class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: cs.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  final bool shareIntent;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onPair;
  const _SignedOutView({
    required this.shareIntent,
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
        // The default intro already explains the account; only the share
        // intent needs the extra how-to caption here.
        if (shareIntent) ...[
          const SizedBox(height: AppDesign.spacingMd),
          _InfoNote(text: _t(context, 'account_sync_share_note')),
        ],
        const SizedBox(height: AppDesign.spacingLg),
        FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: onCreate,
          label: Text(_t(context, 'account_sync_create_account')),
          style: accountSyncPrimaryActionStyle(context),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.login),
          onPressed: onJoin,
          label: Text(_t(context, 'account_sync_join_account')),
          style: accountSyncSecondaryActionStyle(context),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: onPair,
          label: Text(_t(context, 'account_sync_pair_cta')),
          style: accountSyncSecondaryActionStyle(context),
        ),
      ],
    );
  }
}

class _SignedInView extends StatelessWidget {
  final AccountSyncProvider provider;
  final bool shareIntent;
  final VoidCallback onAddDevice;
  final VoidCallback onLogout;
  final VoidCallback onSyncNow;
  final void Function(AccountDevice) onRemoveDevice;
  const _SignedInView({
    required this.provider,
    required this.shareIntent,
    required this.onAddDevice,
    required this.onLogout,
    required this.onSyncNow,
    required this.onRemoveDevice,
  });

  String _t(BuildContext c, String k) => TranslationService.translate(c, k);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConnectedCard(email: provider.status.email),
        const SizedBox(height: AppDesign.spacingMd),
        _InfoNote(
          text: _t(
            context,
            shareIntent ? 'account_sync_share_note' : 'account_sync_intro_note',
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
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
          ...provider.devices.map(
            (d) => _DeviceTile(
              device: d,
              onRemove: d.isSelf ? null : () => onRemoveDevice(d),
              busy: provider.busy,
            ),
          ),
        const SizedBox(height: AppDesign.spacingLg),
        FilledButton.icon(
          icon: const Icon(Icons.sync),
          onPressed: provider.busy ? null : onSyncNow,
          label: Text(_t(context, 'account_sync_sync_now')),
          style: accountSyncPrimaryActionStyle(context),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_to_queue),
          onPressed: onAddDevice,
          label: Text(_t(context, 'account_sync_add_device')),
          style: accountSyncSecondaryActionStyle(context),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        TextButton.icon(
          icon: const Icon(Icons.logout),
          onPressed: provider.busy ? null : onLogout,
          label: Text(_t(context, 'account_sync_logout')),
        ),
      ],
    );
  }
}

/// Shared white surface used by the connected-account card and each device row.
BoxDecoration _syncCardDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? cs.surfaceContainerHighest : Colors.white,
    borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
    border: Border.all(
      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
    ),
  );
}

/// Rounded, primary-tinted badge that hosts an icon in the sync cards.
Widget _syncIconBadge(BuildContext context, IconData icon) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(AppDesign.spacingSm),
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
    ),
    child: Icon(icon, color: cs.primary),
  );
}

/// Picks a device-appropriate glyph from the device's display name.
IconData _deviceIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('ipad') || n.contains('tablet')) return Icons.tablet_mac;
  if (n.contains('iphone') ||
      n.contains('android') ||
      n.contains('phone') ||
      n.contains('pixel') ||
      n.contains('galaxy')) {
    return Icons.smartphone;
  }
  if (n.contains('macbook') || n.contains('laptop')) return Icons.laptop_mac;
  if (n.contains('mac') || n.contains('imac')) return Icons.desktop_mac;
  if (n.contains('windows') ||
      n.contains('linux') ||
      n.contains('desktop') ||
      n.contains(' pc')) {
    return Icons.computer;
  }
  return Icons.devices_other;
}

/// Card at the top of the signed-in view: the account the trousseau is bound to.
class _ConnectedCard extends StatelessWidget {
  final String email;
  const _ConnectedCard({required this.email});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: _syncCardDecoration(context),
      child: Row(
        children: [
          _syncIconBadge(context, Icons.verified_user),
          const SizedBox(width: AppDesign.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(
                    context,
                    'account_sync_signed_in_label',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final AccountDevice device;

  /// Removes this device from the account. Null for the current device, which is
  /// removed via sign out instead.
  final VoidCallback? onRemove;

  /// Whether a request is in flight: the remove button stays visible but disabled
  /// (consistent with the sync / sign-out buttons below the list).
  final bool busy;
  const _DeviceTile({required this.device, this.onRemove, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final selfLabel = TranslationService.translate(
      context,
      'account_sync_this_device',
    );
    final trailing = device.isSelf
        ? _selfBadge(context, selfLabel)
        : _removeButton(context);
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: AppDesign.spacingXs),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: _syncCardDecoration(context),
      child: Row(
        children: [
          _syncIconBadge(context, _deviceIcon(device.name)),
          const SizedBox(width: AppDesign.spacingMd),
          Expanded(
            child: Text(
              device.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDesign.spacingSm),
            trailing,
          ],
        ],
      ),
    );
    // The current device is a purely informational row: merge its label for
    // assistive tech. Other devices carry an interactive "remove" button, so
    // keep their natural semantics (excluding them would hide the button).
    if (device.isSelf) {
      return Semantics(
        label: '${device.name}, $selfLabel',
        excludeSemantics: true,
        child: tile,
      );
    }
    return tile;
  }

  Widget? _removeButton(BuildContext context) {
    if (onRemove == null) return null;
    final label = TranslationService.translate(
      context,
      'account_sync_remove_device_button',
    );
    // The visible label is just "Remove"; give assistive tech the device name too.
    return Semantics(
      button: true,
      enabled: !busy,
      label: '$label, ${device.name}',
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.link_off),
          tooltip: label,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  /// Primary-tinted pill marking the current device.
  Widget _selfBadge(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingSm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesign.radiusRound),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
