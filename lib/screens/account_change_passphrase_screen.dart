import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/passphrase_strength_meter.dart';

/// Change the account passphrase from a signed-in device (ADR-042 lot B).
///
/// The old passphrase is never asked for: this device already holds the
/// account keys, so it re-wraps them under the new passphrase and the hub
/// authenticates the change with the account key. The same strength policy as
/// signup applies (the live meter gates the button), plus a confirmation field
/// because a typo here locks the passphrase path for every future device.
///
/// Same content width as the account screen: a short form, not a settings list.
const double _maxBodyWidth = 560.0;

class AccountChangePassphraseScreen extends StatelessWidget {
  const AccountChangePassphraseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: TranslationService.translate(
          context,
          'account_sync_change_passphrase',
        ),
      ),
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.watch<ThemeProvider>().themeStyle,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxBodyWidth),
                child: AccountChangePassphraseForm(
                  onDone: () => context.pop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The form itself, separated from the app-bar chrome so it can be exercised
/// in widget tests with only the account and theme providers above it.
class AccountChangePassphraseForm extends StatefulWidget {
  /// Called once the passphrase has been changed and confirmed to the reader.
  final VoidCallback onDone;

  const AccountChangePassphraseForm({super.key, required this.onDone});

  @override
  State<AccountChangePassphraseForm> createState() =>
      _AccountChangePassphraseFormState();
}

class _AccountChangePassphraseFormState
    extends State<AccountChangePassphraseForm> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  Timer? _strengthDebounce;
  PassphraseStrength _strength = const PassphraseStrength.empty();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _strengthDebounce?.cancel();
    super.dispose();
  }

  String _t(String key) => TranslationService.translate(context, key);

  void _onPassphraseChanged(String value) {
    // Rebuild now for the confirmation match, score after the debounce.
    setState(() {});
    _strengthDebounce?.cancel();
    _strengthDebounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await context.read<AccountSyncProvider>().checkPassphrase(
        value,
      );
      if (mounted) setState(() => _strength = s);
    });
  }

  bool get _confirmMismatch =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text != _passphraseController.text;

  bool get _canSubmit =>
      !_submitting &&
      _strength.acceptable &&
      _passphraseController.text.isNotEmpty &&
      _confirmController.text == _passphraseController.text;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final provider = context.read<AccountSyncProvider>();
    try {
      await provider.changePassphrase(_passphraseController.text);
      if (!mounted) return;
      _showMessage(_t('account_sync_change_passphrase_done'));
      widget.onDone();
    } on AccountSignupException catch (_) {
      // Only the weak-passphrase backstop reaches here for a change.
      if (!mounted) return;
      _showMessage(_t('account_sync_weak_passphrase'), error: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage(_t('account_sync_change_passphrase_failed'), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('account_sync_change_passphrase_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingLg),
        TextField(
          controller: _passphraseController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _t('account_sync_new_passphrase_label'),
            helperText: _t('account_sync_passphrase_hint'),
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              tooltip: _t(
                _obscure
                    ? 'account_sync_show_passphrase'
                    : 'account_sync_hide_passphrase',
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: _onPassphraseChanged,
        ),
        const SizedBox(height: AppDesign.spacingSm),
        PassphraseStrengthMeter(strength: _strength),
        const SizedBox(height: AppDesign.spacingMd),
        TextField(
          controller: _confirmController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _t('account_sync_change_passphrase_confirm_label'),
            // errorText is announced by screen readers with the field (A1).
            errorText: _confirmMismatch
                ? _t('account_sync_change_passphrase_mismatch')
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppDesign.spacingMd),
        Text(
          _t('account_sync_change_passphrase_note'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppDesign.spacingLg),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_t('account_sync_change_passphrase_submit')),
        ),
      ],
    );
  }
}
