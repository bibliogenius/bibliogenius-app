import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/mdns_service.dart';
import '../services/translation_service.dart';
import '../utils/invite_payload.dart';

/// Generates the invite link and opens the native share sheet directly.
///
/// Shows a brief loading snackbar while generating. Falls back to the
/// full bottom sheet (with QR code + error state) if generation fails.
Future<void> shareInviteLinkDirect(BuildContext context) async {
  // Capture everything from context before any await
  final messenger = ScaffoldMessenger.of(context);
  final apiService = Provider.of<ApiService>(context, listen: false);
  final libraryName = Provider.of<ThemeProvider>(
    context,
    listen: false,
  ).libraryName;
  final loadingText = TranslationService.translate(
    context,
    'generating_invite_link',
  );
  final messageTemplate = TranslationService.translate(
    context,
    'invite_share_message',
  );

  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text(loadingText),
        ],
      ),
      duration: const Duration(seconds: 10),
    ),
  );

  try {
    // Resolve local IP (best-effort for LAN connections)
    String? localIp;
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && !wifiIp.startsWith('169.254.')) {
        localIp = wifiIp;
      }
    } catch (_) {}
    localIp ??= await MdnsService.getValidLanIp();

    final configRes = await apiService.getLibraryConfig();
    final libraryUuid = configRes.data['library_uuid'] as String?;
    final ed25519Key = configRes.data['ed25519_public_key'] as String?;
    final x25519Key = configRes.data['x25519_public_key'] as String?;
    final relayUrl = configRes.data['relay_url'] as String?;
    final mailboxId = configRes.data['mailbox_id'] as String?;
    final relayWriteToken = configRes.data['relay_write_token'] as String?;

    if (localIp == null && (relayUrl == null || mailboxId == null)) {
      messenger.hideCurrentSnackBar();
      // Cannot generate link - fall back to bottom sheet (shows error state)
      if (context.mounted) showInviteShareSheet(context);
      return;
    }

    final peerUrl = localIp != null
        ? "http://$localIp:${ApiService.httpPort}"
        : "";

    final payload = buildInvitePayload(
      name: libraryName,
      url: peerUrl,
      libraryUuid: libraryUuid,
      ed25519PublicKey: ed25519Key,
      x25519PublicKey: x25519Key,
      relayUrl: relayUrl,
      mailboxId: mailboxId,
      relayWriteToken: relayWriteToken,
    );

    final link = await createInviteLink(payload, hubBaseUrl: ApiService.hubUrl);

    messenger.hideCurrentSnackBar();

    final message = messageTemplate
        .replaceAll('{name}', libraryName)
        .replaceAll('{link}', link);

    final box = context.mounted
        ? context.findRenderObject() as RenderBox?
        : null;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await Share.share(message, sharePositionOrigin: origin);
  } catch (e) {
    debugPrint('shareInviteLinkDirect: error: $e');
    messenger.hideCurrentSnackBar();
    if (context.mounted) showInviteShareSheet(context);
  }
}

/// Shows the invite share bottom sheet.
///
/// Call this from any context to display the invite link + QR code sheet.
void showInviteShareSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const InviteShareSheet(),
  );
}

/// Bottom sheet that displays a QR code, library name, and
/// Copy / Share buttons for the invite link.
class InviteShareSheet extends StatefulWidget {
  const InviteShareSheet({super.key});

  @override
  State<InviteShareSheet> createState() => _InviteShareSheetState();
}

class _InviteShareSheetState extends State<InviteShareSheet> {
  String? _libraryName;
  String? _inviteLink;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Resolve local IP (best-effort for LAN connections)
      String? localIp;
      try {
        final info = NetworkInfo();
        final wifiIp = await info.getWifiIP();
        if (wifiIp != null && !wifiIp.startsWith('169.254.')) {
          localIp = wifiIp;
        }
      } catch (_) {}
      localIp ??= await MdnsService.getValidLanIp();

      final configRes = await apiService.getLibraryConfig();
      // Library name from ThemeProvider (single source of truth)
      final libraryName = Provider.of<ThemeProvider>(
        context,
        listen: false,
      ).libraryName;
      final libraryUuid = configRes.data['library_uuid'] as String?;
      final ed25519Key = configRes.data['ed25519_public_key'] as String?;
      final x25519Key = configRes.data['x25519_public_key'] as String?;
      final relayUrl = configRes.data['relay_url'] as String?;
      final mailboxId = configRes.data['mailbox_id'] as String?;
      final relayWriteToken = configRes.data['relay_write_token'] as String?;

      // No WiFi IP AND no relay credentials: cannot generate invite
      if (localIp == null && (relayUrl == null || mailboxId == null)) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Build URL: use LAN URL if available, empty string for relay-only
      final peerUrl = localIp != null
          ? "http://$localIp:${ApiService.httpPort}"
          : "";

      final payload = buildInvitePayload(
        name: libraryName,
        url: peerUrl,
        libraryUuid: libraryUuid,
        ed25519PublicKey: ed25519Key,
        x25519PublicKey: x25519Key,
        relayUrl: relayUrl,
        mailboxId: mailboxId,
        relayWriteToken: relayWriteToken,
      );

      // Try to create a short invite link via the hub
      final link = await createInviteLink(
        payload,
        hubBaseUrl: ApiService.hubUrl,
      );

      if (mounted) {
        setState(() {
          _libraryName = libraryName;
          _inviteLink = link;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('InviteShareSheet: error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  void _copyLink() {
    if (_inviteLink == null) return;
    Clipboard.setData(ClipboardData(text: _inviteLink!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'invite_link_copied'),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareLink() async {
    if (_inviteLink == null) return;
    final name = _libraryName ?? 'BiblioGenius';
    final message = TranslationService.translate(
      context,
      'invite_share_message',
    ).replaceAll('{name}', name).replaceAll('{link}', _inviteLink!);

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    try {
      await Share.share(message, sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('InviteShareSheet: share failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.translate(context, 'share_failed')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, 'invite_share_title'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_inviteLink == null)
              _buildErrorState(theme)
            else
              _buildContent(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            TranslationService.translate(context, 'qr_error'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'qr_wifi_suggestion'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    // Truncate URL for display
    final displayUrl = _inviteLink != null && _inviteLink!.length > 40
        ? '${_inviteLink!.substring(0, 37)}...'
        : _inviteLink ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR + info row
        Row(
          children: [
            // Compact QR code
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 120,
                height: 120,
                child: QrImageView(
                  data: _inviteLink!,
                  version: QrVersions.auto,
                  size: 120,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Library name + truncated URL
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _libraryName ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Info: works on any network
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cell_tower,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslationService.translate(
                    context,
                    'invite_works_everywhere',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Buttons row
        Row(
          children: [
            Expanded(
              child: _isDesktop
                  ? FilledButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.content_copy, size: 18),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'copy_invite_link',
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.content_copy, size: 18),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'copy_invite_link',
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _isDesktop
                  ? OutlinedButton.icon(
                      onPressed: _shareLink,
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'share_invite_link',
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _shareLink,
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'share_invite_link',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
