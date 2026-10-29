import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/contextual_help_sheet.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/translation_service.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Account and devices accordion: the encrypted account (backup, recovery
/// after a loss, other devices), shared access, two-factor authentication
/// and the session.
class AccountSettingsSection extends StatefulWidget {
  const AccountSettingsSection({super.key});

  @override
  State<AccountSettingsSection> createState() => _AccountSettingsSectionState();
}

class _AccountSettingsSectionState extends State<AccountSettingsSection> {
  SettingsData get _data => settingsDataOf(context);

  @override
  Widget build(BuildContext context) {
    final mfaEnabled = _data.userInfo?['mfa_enabled'] ?? false;
    final hasPassword = _data.userInfo?['has_password'] ?? false;
    if (!settingsMatches(context, [
      'settings_account_devices_title',
      'account_sync_title',
      'account_sync_settings_subtitle',
      'settings_linked_devices',
      'settings_goal_sync_devices',
      'account_share_access_title',
      'two_factor_auth',
      if (hasPassword) 'logout',
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsAccordion(
      name: 'account',
      icon: Icons.devices,
      titleKey: 'settings_account_devices_title',
      children: [
        const AccountSyncTile(),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: Text(
            TranslationService.translate(context, 'account_share_access_title'),
          ),
          subtitle: Text(
            TranslationService.translate(context, 'account_share_access_desc'),
          ),
          trailing: const Icon(Icons.chevron_right),
          // Same account screen, share-intent framing (title
          // + caption acknowledge the tapped entry).
          onTap: () => context.push('/account-sync?intent=share'),
        ),
        // Honest note on the shared-account trust model: every
        // holder of the passphrase has full access, and durable
        // revocation does not exist yet.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            TranslationService.translate(context, 'account_shared_trust_note'),
            // Themed muted color: grey[600] fails the AA
            // contrast ratio on dark-theme cards.
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (!Provider.of<ApiService>(context, listen: false).useFfi)
          ListTile(
            leading: const Icon(Icons.security),
            title: Text(
              TranslationService.translate(context, 'two_factor_auth') ??
                  'Two-Factor Authentication',
            ),
            subtitle: Text(
              mfaEnabled
                  ? (TranslationService.translate(context, 'enabled') ??
                        'Enabled')
                  : (TranslationService.translate(context, 'disabled') ??
                        'Disabled'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HelpAffordance(topicId: 'two_factor_auth_setting'),
                const SizedBox(width: 4),
                Semantics(
                  // The tile's title sits outside the
                  // switch's own node.
                  label: TranslationService.translate(
                    context,
                    'two_factor_auth',
                  ),
                  child: Switch(
                    value: mfaEnabled,
                    onChanged: (val) {
                      if (val) {
                        _setupMfa();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        // Session / Logout (only shown for authenticated users)
        if (hasPassword)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OutlinedButton.icon(
              onPressed: () async {
                final authService = Provider.of<AuthService>(
                  context,
                  listen: false,
                );
                await Future.delayed(const Duration(milliseconds: 200));
                await authService.logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
              icon: const Icon(Icons.logout),
              label: Text(TranslationService.translate(context, 'logout')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                foregroundColor: Colors.red,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _setupMfa() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final response = await apiService.setup2Fa();
      final data = response.data;
      final secret = data['secret'];
      final qrCode = data['qr_code'];

      if (!mounted) return;

      final codeController = TextEditingController();
      String? verifyError;

      await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              TranslationService.translate(context, 'setup_2fa') ?? 'Setup 2FA',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TranslationService.translate(context, 'scan_qr_code') ??
                        'Scan this QR code with your authenticator app:',
                  ),
                  const SizedBox(height: 16),
                  if (qrCode != null)
                    // The secret is offered as selectable text below; the
                    // QR itself has nothing to say to a screen reader.
                    Image.memory(
                      base64Decode(qrCode),
                      height: 200,
                      width: 200,
                      excludeFromSemantics: true,
                    ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '${TranslationService.translate(context, 'secret_key') ?? 'Secret Key'}: $secret',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'verification_code',
                          ) ??
                          'Verification Code',
                      errorText: verifyError,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  TranslationService.translate(context, 'cancel') ?? 'Cancel',
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => verifyError = null);
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'invalid_code',
                          ) ??
                          'Invalid code',
                    );
                    return;
                  }

                  try {
                    await apiService.verify2Fa(secret, code);
                    if (mounted) {
                      Navigator.pop(context);
                      _data.reload();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'mfa_enabled_success',
                                ) ??
                                'MFA Enabled Successfully',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'verification_failed',
                          ) ??
                          'Verification failed',
                    );
                  }
                },
                child: Text(
                  TranslationService.translate(context, 'verify') ?? 'Verify',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_initializing_mfa') ?? 'Error initializing MFA'}: $e',
            ),
          ),
        );
      }
    }
  }
}

/// Tile pointing to the encrypted-account hub (backup + recovery + shared
/// access). Reused by the "Account and devices" accordion (default: pushes
/// the hub screen) and the backup capability sheet ([onTap] swaps the sheet
/// content in place instead of stacking a full screen on the popin).
class AccountSyncTile extends StatelessWidget {
  const AccountSyncTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(TranslationService.translate(context, 'account_sync_title')),
      subtitle: Text(
        TranslationService.translate(context, 'account_sync_settings_subtitle'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap ?? () => context.push('/account-sync'),
    );
  }
}
