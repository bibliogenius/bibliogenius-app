import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/account_sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';

/// Which side of the in-person pairing handshake this device plays. The role is
/// fixed by sign-in state (a signed-out device can only be the new one; a
/// signed-in device can only authorize), so it is passed in, never chosen.
enum AccountPairingRole { newDevice, authorizer }

/// Authenticated QR pairing to add a device to an account (ADR-045).
/// New device: shows its `bg-pair` code, then scans the `bg-sealed`
/// code returned to it. Authorizer: scans the new device's `bg-pair` code, then
/// shows the `bg-sealed` code back.
///
/// SECURITY (ADR-045 / ADR-042 §14 H2): the trousseau is sealed to the X25519
/// key carried in the SCANNED `bg-pair` code, never a relayed value. The
/// security note is shown on every step so the user only ever scans in person.
class AccountAddDeviceScreen extends StatefulWidget {
  final AccountPairingRole role;
  const AccountAddDeviceScreen({super.key, required this.role});

  @override
  State<AccountAddDeviceScreen> createState() => _AccountAddDeviceScreenState();
}

class _AccountAddDeviceScreenState extends State<AccountAddDeviceScreen> {
  final _deviceNameController = TextEditingController(
    text: defaultTargetPlatform.name,
  );

  bool _busy = false;

  // New-device role: this device's `bg-pair` payload once generated.
  String? _pairPayload;

  // Authorizer role: the `bg-sealed` payload to show back, once produced.
  String? _sealedPayload;

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  String _t(String key) => TranslationService.translate(context, key);

  AccountSyncProvider get _provider => context.read<AccountSyncProvider>();

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  // --- New-device role ---

  Future<void> _generatePairCode() async {
    final name = _deviceNameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final payload = await _provider.getDevicePairingQr(name);
      if (!mounted) return;
      setState(() => _pairPayload = payload);
    } catch (e) {
      _showError(_t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAuthorization() async {
    final sealed = await _pushScan(
      title: _t('account_sync_pairing_scan_authorization'),
      instruction: _t('account_sync_scan_instruction'),
      expectedToken: 'bg-sealed',
    );
    if (sealed == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _provider.enrollFromSealed(sealed);
      if (!mounted) return;
      _showSnack(_t('account_sync_device_added'));
      context.pop();
    } catch (e) {
      _showError(_t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Authorizer role ---

  Future<void> _scanNewDevice() async {
    final pairPayload = await _pushScan(
      title: _t('account_sync_pairing_scan_new_device'),
      instruction: _t('account_sync_scan_instruction'),
      expectedToken: 'bg-pair',
    );
    if (pairPayload == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final sealed = await _provider.authorizeDevice(pairPayload);
      if (!mounted) return;
      setState(() => _sealedPayload = sealed);
    } catch (e) {
      _showError(_t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pushScan({
    required String title,
    required String instruction,
    required String expectedToken,
  }) {
    return context.push<String>(
      '/account-sync/scan',
      extra: {
        'title': title,
        'instruction': instruction,
        'token': expectedToken,
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(title: _t('account_sync_add_device_title')),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.watch<ThemeProvider>().themeStyle,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: widget.role == AccountPairingRole.newDevice
                ? _buildNewDevice()
                : _buildAuthorizer(),
          ),
        ),
      ),
    );
  }

  Widget _buildNewDevice() {
    final hasCode = _pairPayload != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('account_sync_pairing_new_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        const _SecurityNote(),
        const SizedBox(height: AppDesign.spacingLg),
        if (!hasCode) ...[
          TextField(
            controller: _deviceNameController,
            decoration: InputDecoration(
              labelText: _t('account_sync_device_name_label'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_2),
            onPressed:
                _busy || _deviceNameController.text.trim().isEmpty
                ? null
                : _generatePairCode,
            label: Text(_t('account_sync_add_device')),
          ),
        ] else ...[
          _QrCard(
            data: _pairPayload!,
            semanticLabel: _t('account_sync_add_device_title'),
          ),
          const SizedBox(height: AppDesign.spacingLg),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _busy ? null : _scanAuthorization,
            label: Text(_t('account_sync_pairing_scan_authorization')),
          ),
        ],
      ],
    );
  }

  Widget _buildAuthorizer() {
    final hasSealed = _sealedPayload != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hasSealed
              ? _t('account_sync_pairing_sealed_intro')
              : _t('account_sync_pairing_authorize_intro'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppDesign.spacingMd),
        const _SecurityNote(),
        const SizedBox(height: AppDesign.spacingLg),
        if (!hasSealed)
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _busy ? null : _scanNewDevice,
            label: Text(_t('account_sync_pairing_scan_new_device')),
          )
        else ...[
          _QrCard(
            data: _sealedPayload!,
            semanticLabel: _t('account_sync_pairing_sealed_intro'),
          ),
          const SizedBox(height: AppDesign.spacingLg),
          FilledButton(
            onPressed: () => context.pop(),
            child: Text(_t('done')),
          ),
        ],
      ],
    );
  }
}

/// A QR code on a guaranteed-light background (QR needs light to scan), centered.
class _QrCard extends StatelessWidget {
  final String data;
  final String semanticLabel;
  const _QrCard({required this.data, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: semanticLabel,
        image: true,
        child: Container(
          padding: const EdgeInsets.all(AppDesign.spacingMd),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 240,
            // Degrade gracefully if a payload ever exceeds single-QR capacity
            // instead of throwing during build.
            errorStateBuilder: (context, error) => SizedBox(
              width: 240,
              height: 240,
              child: Center(
                child: Text(
                  TranslationService.translate(context, 'error_generic'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            // Force dark modules on the white card regardless of app theme.
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// The ADR-045 authenticated-channel warning, surfaced on every pairing step.
class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

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
          Icon(Icons.shield_outlined, color: cs.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              TranslationService.translate(
                context,
                'account_sync_pairing_security_note',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
