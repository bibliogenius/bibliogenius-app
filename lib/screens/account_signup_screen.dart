import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/account_sync_restart_dialog.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/passphrase_strength_meter.dart';
import '../widgets/recovery_phrase_view.dart';

/// Create-a-new-account flow.
///
/// Two phases in one screen: (1) the form with a live, debounced passphrase
/// strength meter that gates the submit button on `acceptable`; (2) the one-time
/// BIP39 recovery phrase, shown after signup with a "saved it" confirmation.
/// A duplicate email is routed to the join flow ([AccountSignupException]).
class AccountSignupScreen extends StatefulWidget {
  const AccountSignupScreen({super.key});

  @override
  State<AccountSignupScreen> createState() => _AccountSignupScreenState();
}

class _AccountSignupScreenState extends State<AccountSignupScreen> {
  final _emailController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _deviceNameController = TextEditingController(
    text: defaultTargetPlatform.name,
  );

  Timer? _strengthDebounce;
  PassphraseStrength _strength = const PassphraseStrength.empty();
  bool _obscure = true;
  bool _submitting = false;

  // Recovery phase: non-null once signup succeeds.
  String? _recoveryPhrase;
  bool _savedConfirmed = false;
  // Data sync activates only after an app restart (the backend CRR-ifies the
  // database on the next launch); prompt for it when the user leaves the screen.
  bool _restartRequired = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passphraseController.dispose();
    _deviceNameController.dispose();
    _strengthDebounce?.cancel();
    super.dispose();
  }

  String _t(String key) => TranslationService.translate(context, key);

  void _onPassphraseChanged(String value) {
    _strengthDebounce?.cancel();
    _strengthDebounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await context.read<AccountSyncProvider>().checkPassphrase(
        value,
      );
      if (mounted) setState(() => _strength = s);
    });
  }

  bool get _emailLooksValid {
    final e = _emailController.text.trim();
    return e.contains('@') && e.contains('.') && e.length >= 5;
  }

  bool get _canSubmit =>
      !_submitting &&
      _emailLooksValid &&
      _deviceNameController.text.trim().isNotEmpty &&
      _strength.acceptable;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final provider = context.read<AccountSyncProvider>();
    try {
      final result = await provider.signup(
        email: _emailController.text.trim(),
        passphrase: _passphraseController.text,
        deviceName: _deviceNameController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _recoveryPhrase = result.recoveryPhrase;
        _restartRequired = result.restartRequired;
      });
    } on AccountSignupException catch (e) {
      if (!mounted) return;
      if (e.accountExists) {
        await _offerSignIn();
      } else {
        _showError(_t('account_sync_weak_passphrase'));
      }
    } catch (e) {
      if (!mounted) return;
      _showError(_t('error_generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Leave the recovery-phrase screen, prompting for the activation restart first
  /// if the backend asked for one.
  Future<void> _finishRecovery() async {
    if (_restartRequired) await showAccountSyncRestartDialog(context);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _offerSignIn() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(_t('account_sync_account_exists')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('account_sync_account_exists_action')),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      // Replace this screen with the join flow, prefilling the email.
      context.pushReplacement('/account-sync/join', extra: {
        'email': _emailController.text.trim(),
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inRecovery = _recoveryPhrase != null;
    return PopScope(
      // During the recovery phase, block accidental back-navigation: the phrase
      // is shown once and the account already exists, so leaving without saving
      // is irreversible. Only allow it once the user confirms.
      canPop: !inRecovery || _savedConfirmed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inRecovery) {
          _showError(_t('account_sync_recovery_warning'));
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GenieAppBar(
          title: _t(
            inRecovery ? 'account_sync_recovery_title' : 'account_sync_signup_title',
          ),
          automaticallyImplyLeading: !inRecovery,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: AppDesign.pageGradientForTheme(
              context.watch<ThemeProvider>().themeStyle,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              child: inRecovery ? _buildRecovery() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('account_sync_signup_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingLg),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _t('account_sync_email_label'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppDesign.spacingMd),
        TextField(
          controller: _passphraseController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _t('account_sync_passphrase_label'),
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
          controller: _deviceNameController,
          decoration: InputDecoration(
            labelText: _t('account_sync_device_name_label'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
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
              : Text(_t('account_sync_create_button')),
        ),
      ],
    );
  }

  Widget _buildRecovery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('account_sync_recovery_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        _WarningBanner(text: _t('account_sync_recovery_warning')),
        const SizedBox(height: AppDesign.spacingMd),
        RecoveryPhraseView(phrase: _recoveryPhrase!),
        const SizedBox(height: AppDesign.spacingMd),
        CheckboxListTile(
          value: _savedConfirmed,
          onChanged: (v) => setState(() => _savedConfirmed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(_t('account_sync_recovery_confirm_checkbox')),
        ),
        const SizedBox(height: AppDesign.spacingSm),
        FilledButton(
          onPressed: _savedConfirmed ? _finishRecovery : null,
          child: Text(_t('account_sync_recovery_confirm_button')),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: cs.onErrorContainer),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
