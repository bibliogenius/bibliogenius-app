import 'dart:convert';

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

  /// Manually trigger one sync cycle and show a human confirmation. The backend
  /// returns JSON (`{synced, applied?, pushed?}`); we translate it into a plain
  /// message instead of surfacing the raw payload.
  Future<void> _syncNow() async {
    String message;
    try {
      final result = await _provider.syncNow();
      final json = jsonDecode(result) as Map<String, dynamic>;
      if (json['reason'] == 'restart_required') {
        // Enrolled but not yet restarted: sync activates on the next launch.
        message = _t('account_sync_restart_required_body');
      } else {
        final applied = (json['applied'] as num?)?.toInt() ?? 0;
        final pushed = (json['pushed'] as num?)?.toInt() ?? 0;
        message = (applied == 0 && pushed == 0)
            ? _t('account_sync_synced_uptodate')
            : _t('account_sync_synced_done');
      }
    } catch (_) {
      message = _t('account_sync_sync_failed');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                          onSyncNow: _syncNow,
                          onRemoveDevice: _confirmRemoveDevice,
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
      ],
    );
  }
}

class _SignedInView extends StatelessWidget {
  final AccountSyncProvider provider;
  final VoidCallback onAddDevice;
  final VoidCallback onLogout;
  final VoidCallback onSyncNow;
  final void Function(AccountDevice) onRemoveDevice;
  const _SignedInView({
    required this.provider,
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
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            ),
          ),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_to_queue),
          onPressed: onAddDevice,
          label: Text(_t(context, 'account_sync_add_device')),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            ),
          ),
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
