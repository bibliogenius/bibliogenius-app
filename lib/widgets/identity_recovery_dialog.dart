import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;

/// Stable error prefix emitted by `IdentityError::DecryptionFailed::Display` on
/// the Rust side. Flutter pattern-matches the FFI exception against this so
/// the recovery flow only triggers on the typed identity wipe scenario, not
/// on unrelated init failures.
const String identityDecryptFailedPrefix = 'E_IDENTITY_DECRYPT_FAILED';

/// Returns true when an init/get_public_keys exception thrown by the FFI
/// surface corresponds to a decryption failure that requires user-confirmed
/// recovery (storage swing on macOS, etc.).
bool isIdentityDecryptFailure(Object error) =>
    error.toString().contains(identityDecryptFailedPrefix);

/// One device or peer that the user must re-pair after a successful
/// "Repartir de zéro". `isDevice == true` means a linked device, otherwise
/// it is a peer library.
@immutable
class IdentityRepairTarget {
  final String label;
  final bool isDevice;
  const IdentityRepairTarget({required this.label, required this.isDevice});
}

/// Loader signature used by [IdentityRecoveryDialog]. Production wires this
/// to `ApiService.getPeers()` + `frb.deviceListLinked()`. Tests inject a stub
/// so the dialog can be rendered without FFI or Provider plumbing.
typedef IdentityRepairTargetsLoader =
    Future<List<IdentityRepairTarget>> Function(BuildContext context);

/// Blocking dialog shown when the stored E2EE identity cannot be decrypted
/// with the supplied `library_uuid`. The user must explicitly choose to
/// retry (most common when a transient storage glitch resolves itself) or
/// regenerate the identity (which breaks every paired peer and forces them
/// to re-pair).
///
/// Rationale: the Rust layer used to silently wipe the row in this case,
/// which broke iPhone↔Mac sync without any signal. See
/// `memory/e2ee_identity_storage_fragility.md`.
class IdentityRecoveryDialog extends StatefulWidget {
  final String libraryUuid;

  /// Override the loader for tests. Defaults to fetching peers via
  /// `ApiService` and linked devices via the Rust FFI.
  final IdentityRepairTargetsLoader? repairTargetsLoader;

  /// Test-only: when provided, opens the dialog directly in the success
  /// state with this list of targets, bypassing the regenerate FFI flow.
  @visibleForTesting
  final List<IdentityRepairTarget>? debugInitialTargets;

  const IdentityRecoveryDialog({
    super.key,
    required this.libraryUuid,
    this.repairTargetsLoader,
    @visibleForTesting this.debugInitialTargets,
  });

  /// Shows the dialog as a barrier-locked modal and resolves once the user
  /// has either recovered the identity (retry success or regenerate) or the
  /// caller closes the dialog programmatically. The future completes with
  /// `true` on recovery, `false` if the dialog was dismissed without one.
  static Future<bool> show({
    required BuildContext context,
    required String libraryUuid,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: IdentityRecoveryDialog(libraryUuid: libraryUuid),
      ),
    );
    return result ?? false;
  }

  @override
  State<IdentityRecoveryDialog> createState() => _IdentityRecoveryDialogState();
}

class _IdentityRecoveryDialogState extends State<IdentityRecoveryDialog> {
  bool _busy = false;
  String? _errorMessage;
  bool _regenSucceeded = false;
  List<IdentityRepairTarget>? _repairTargets;

  @override
  void initState() {
    super.initState();
    final initial = widget.debugInitialTargets;
    if (initial != null) {
      _regenSucceeded = true;
      _repairTargets = initial;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await frb.initIdentityFfi(libraryUuid: widget.libraryUuid);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = isIdentityDecryptFailure(e)
            ? TranslationService.translate(
                context,
                'identity_recovery_retry_still_failing',
              )
            : TranslationService.translate(
                context,
                'identity_recovery_retry_unexpected_error',
                params: {'error': e.toString()},
              );
      });
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(ctx, 'identity_recovery_confirm_title'),
        ),
        content: Text(
          TranslationService.translate(ctx, 'identity_recovery_confirm_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              TranslationService.translate(
                ctx,
                'identity_recovery_btn_regenerate',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await frb.confirmRegenerateIdentityFfi(libraryUuid: widget.libraryUuid);
      if (!mounted) return;
      // Load peers + linked devices before showing success so the user sees a
      // single transition (spinner -> populated list) instead of the list
      // popping in after they have already read the dialog.
      final loader = widget.repairTargetsLoader ?? _defaultLoader;
      final targets = await loader(context);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _regenSucceeded = true;
        _repairTargets = targets;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = TranslationService.translate(
          context,
          'identity_recovery_regen_failed',
          params: {'error': e.toString()},
        );
      });
    }
  }

  /// Production loader. Reads peers from the local HTTP API (filtered to
  /// `key_exchange_done == true`) and linked devices from the Rust FFI. Any
  /// failure on either side degrades gracefully to an empty list, so the
  /// success state falls back to the generic "OK" view rather than blocking
  /// the user behind a load error.
  Future<List<IdentityRepairTarget>> _defaultLoader(
    BuildContext context,
  ) async {
    ApiService api;
    try {
      api = context.read<ApiService>();
    } catch (_) {
      return const [];
    }

    final results = await Future.wait<dynamic>([
      _fetchPeersSafe(api),
      _fetchLinkedDevicesSafe(),
    ]);

    final peerEntries = results[0] as List<IdentityRepairTarget>;
    final deviceEntries = results[1] as List<IdentityRepairTarget>;
    // Devices first (the user owns them and will recognize them), peers next.
    return [...deviceEntries, ...peerEntries];
  }

  Future<List<IdentityRepairTarget>> _fetchPeersSafe(ApiService api) async {
    try {
      final Response<dynamic> resp = await api.getPeers();
      if (resp.statusCode != 200) return const [];
      final raw = (resp.data is Map) ? (resp.data as Map)['data'] : null;
      if (raw is! List) return const [];
      final out = <IdentityRepairTarget>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final ked = entry['key_exchange_done'];
        if (ked != true && ked != 1) continue;
        final display = (entry['display_name'] as String?)?.trim();
        final name = (entry['name'] as String?)?.trim() ?? '';
        final label = (display != null && display.isNotEmpty) ? display : name;
        if (label.isEmpty) continue;
        out.add(IdentityRepairTarget(label: label, isDevice: false));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<IdentityRepairTarget>> _fetchLinkedDevicesSafe() async {
    try {
      final devices = await frb.deviceListLinked();
      return [
        for (final d in devices)
          if (d.name.trim().isNotEmpty)
            IdentityRepairTarget(label: d.name.trim(), isDevice: true),
      ];
    } catch (_) {
      return const [];
    }
  }

  void _goToNetwork() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(true);
    router.go('/network');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_regenSucceeded) {
      final targets = _repairTargets ?? const <IdentityRepairTarget>[];
      if (targets.isEmpty) {
        return _buildGenericSuccess(theme);
      }
      return _buildRepairSuccess(theme, targets);
    }

    return AlertDialog(
      icon: Icon(Icons.lock_reset, color: theme.colorScheme.error, size: 32),
      title: Text(
        TranslationService.translate(context, 'identity_recovery_title'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TranslationService.translate(context, 'identity_recovery_body'),
          ),
          const SizedBox(height: 12),
          Text(
            '${TranslationService.translate(context, 'identity_recovery_bullet_retry')}\n'
            '${TranslationService.translate(context, 'identity_recovery_bullet_regenerate')}',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _regenerate,
          child: Text(
            TranslationService.translate(
              context,
              'identity_recovery_btn_regenerate',
            ),
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _retry,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(TranslationService.translate(context, 'retry')),
        ),
      ],
    );
  }

  Widget _buildGenericSuccess(ThemeData theme) {
    return AlertDialog(
      icon: Icon(
        Icons.check_circle,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(
        TranslationService.translate(
          context,
          'identity_recovery_success_title',
        ),
      ),
      content: Text(
        TranslationService.translate(
          context,
          'identity_recovery_success_body',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            TranslationService.translate(
              context,
              'identity_recovery_success_btn',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRepairSuccess(
    ThemeData theme,
    List<IdentityRepairTarget> targets,
  ) {
    final count = targets.length;
    final titleKey = count == 1
        ? 'identity_recovery_success_repair_title_one'
        : 'identity_recovery_success_repair_title_other';
    final title = TranslationService.translate(
      context,
      titleKey,
      params: {'count': count.toString()},
    );
    final intro = TranslationService.translate(
      context,
      'identity_recovery_success_repair_intro',
    );
    final deviceIconLabel = TranslationService.translate(
      context,
      'identity_recovery_success_icon_device_label',
    );
    final peerIconLabel = TranslationService.translate(
      context,
      'identity_recovery_success_icon_peer_label',
    );
    final goNetworkLabel = TranslationService.translate(
      context,
      'identity_recovery_success_btn_network',
    );
    final laterLabel = TranslationService.translate(
      context,
      'identity_recovery_success_btn_later',
    );

    return AlertDialog(
      icon: Icon(
        Icons.check_circle,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Semantics(
        header: true,
        child: Text(title),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(intro),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in targets)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        t.isDevice ? Icons.devices : Icons.person,
                        semanticLabel: t.isDevice
                            ? deviceIconLabel
                            : peerIconLabel,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(t.label),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        Semantics(
          button: true,
          label: laterLabel,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(laterLabel),
          ),
        ),
        Semantics(
          button: true,
          label: goNetworkLabel,
          child: FilledButton(
            onPressed: _goToNetwork,
            child: Text(goNetworkLabel),
          ),
        ),
      ],
    );
  }
}
