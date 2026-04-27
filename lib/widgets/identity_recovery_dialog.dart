import 'package:flutter/material.dart';

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

  const IdentityRecoveryDialog({super.key, required this.libraryUuid});

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
      setState(() {
        _busy = false;
        _regenSucceeded = true;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_regenSucceeded) {
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
}
