import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';

/// Join an EXISTING account on this device with its passphrase (ST-05 Phase F,
/// Path A). Reached from the hub, or from the signup flow when the email is
/// already registered (the email is then prefilled).
class AccountJoinScreen extends StatefulWidget {
  final String? initialEmail;
  const AccountJoinScreen({super.key, this.initialEmail});

  @override
  State<AccountJoinScreen> createState() => _AccountJoinScreenState();
}

class _AccountJoinScreenState extends State<AccountJoinScreen> {
  late final TextEditingController _emailController;
  final _passphraseController = TextEditingController();
  final _deviceNameController = TextEditingController(
    text: defaultTargetPlatform.name,
  );

  bool _obscure = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passphraseController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  String _t(String key) => TranslationService.translate(context, key);

  bool get _emailLooksValid {
    final e = _emailController.text.trim();
    return e.contains('@') && e.contains('.') && e.length >= 5;
  }

  bool get _canSubmit =>
      !_submitting &&
      _emailLooksValid &&
      _passphraseController.text.isNotEmpty &&
      _deviceNameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final provider = context.read<AccountSyncProvider>();
    try {
      await provider.joinWithPassphrase(
        email: _emailController.text.trim(),
        passphrase: _passphraseController.text,
        deviceName: _deviceNameController.text.trim(),
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('account_sync_join_failed')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(title: _t('account_sync_join_title')),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.watch<ThemeProvider>().themeStyle,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('account_sync_join_intro'),
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
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      tooltip: _t(
                        _obscure
                            ? 'account_sync_show_passphrase'
                            : 'account_sync_hide_passphrase',
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
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
                      : Text(_t('account_sync_join_button')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
