import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../utils/invite_payload.dart';

/// Produces the invite to display; injectable so the screen can be tested
/// without the network. Defaults to [loadInviteLink] against the backend.
typedef InviteLoader = Future<InviteLinkData?> Function();

/// Opens the invite screen as a full-screen dialog.
///
/// The keys (`showMyCodeDialog`, `closeShowMyCode`, `myQrCode`, ...) are the
/// ones the integration tour drives; keep them when reworking the screen.
Future<void> showInviteScreen(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => const InviteScreen(),
  );
}

/// The one screen that shows this library's invitation: what a connection
/// gives, the QR code for pairing in person, the link for pairing remotely.
class InviteScreen extends StatefulWidget {
  final InviteLoader? loader;

  const InviteScreen({super.key, this.loader});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  InviteLinkData? _invite;
  bool _isLoading = true;
  late final String _libraryName;

  @override
  void initState() {
    super.initState();
    _libraryName = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).libraryName;
    _load();
  }

  Future<void> _load() async {
    if (!_isLoading) setState(() => _isLoading = true);
    final loader = widget.loader ?? _defaultLoader();
    final invite = await loader();
    if (!mounted) return;
    setState(() {
      _invite = invite;
      _isLoading = false;
    });
  }

  InviteLoader _defaultLoader() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return () => loadInviteLink(
      libraryName: _libraryName,
      fetchLibraryConfig: () async =>
          (await apiService.getLibraryConfig()).data as Map,
      httpPort: ApiService.httpPort,
      hubBaseUrl: ApiService.hubUrl,
    );
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  void _copyLink() {
    final link = _invite?.link;
    if (link == null) return;
    Clipboard.setData(ClipboardData(text: link));
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

  Future<void> _shareLink(BuildContext buttonContext) async {
    final link = _invite?.link;
    if (link == null) return;
    final message = TranslationService.translate(
      context,
      'invite_share_message',
    ).replaceAll('{name}', _libraryName).replaceAll('{link}', link);

    // Anchor the share popover on the button (required on iPad).
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    try {
      await Share.share(message, sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('InviteScreen: share failed: $e');
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
    return Scaffold(
      key: const Key('showMyCodeDialog'),
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'invite_screen_title'),
        ),
        leading: IconButton(
          key: const Key('closeShowMyCode'),
          icon: const Icon(Icons.close),
          tooltip: TranslationService.translate(context, 'close'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? _LoadingState()
            : _invite == null
            ? _UnavailableState(onRetry: _load)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _InviteContent(
                  invite: _invite!,
                  isDesktop: _isDesktop,
                  onCopy: _copyLink,
                  onShare: _shareLink,
                ),
              ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: TranslationService.translate(context, 'generating_invite_link'),
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

/// Neither a Wi-Fi address nor relay credentials: nothing another library
/// could reach. Shared by every surface that used to carry its own copy.
class _UnavailableState extends StatelessWidget {
  final VoidCallback onRetry;

  const _UnavailableState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'invite_unavailable_title'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'qr_wifi_suggestion'),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('retryInviteBtn'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(TranslationService.translate(context, 'retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteContent extends StatelessWidget {
  final InviteLinkData invite;
  final bool isDesktop;
  final VoidCallback onCopy;
  final void Function(BuildContext buttonContext) onShare;

  const _InviteContent({
    required this.invite,
    required this.isDesktop,
    required this.onCopy,
    required this.onShare,
  });

  /// Relay credentials travel as the `mi` (mailbox id) key of the payload;
  /// without them the link only reaches this library on its own Wi-Fi.
  bool get _reachableRemotely => invite.payload.containsKey('mi');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TranslationService.translate(context, 'invite_intro'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),

        _SectionTitle(
          icon: Icons.qr_code_2,
          text: TranslationService.translate(context, 'invite_in_person_title'),
        ),
        const SizedBox(height: 8),
        Text(
          TranslationService.translate(context, 'invite_in_person_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // The QR code needs a light, opaque background to scan in dark mode.
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              key: const Key('myQrCode'),
              data: invite.link,
              version: QrVersions.auto,
              size: 200,
              semanticsLabel: TranslationService.translate(
                context,
                'invite_qr_semantics',
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),

        _SectionTitle(
          icon: Icons.send_outlined,
          text: TranslationService.translate(context, 'invite_remote_title'),
        ),
        const SizedBox(height: 8),
        Text(
          TranslationService.translate(context, 'invite_remote_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _ReachNote(
          icon: _reachableRemotely ? Icons.cell_tower : Icons.wifi,
          text: TranslationService.translate(
            context,
            _reachableRemotely ? 'invite_works_everywhere' : 'invite_lan_only',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                key: const Key('copyInviteLinkBtn'),
                filled: isDesktop,
                icon: Icons.content_copy,
                label: TranslationService.translate(
                  context,
                  'copy_invite_link',
                ),
                onPressed: (_) => onCopy(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                key: const Key('shareInviteLinkBtn'),
                filled: !isDesktop,
                icon: Icons.share,
                label: TranslationService.translate(context, 'invite_send'),
                onPressed: onShare,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReachNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ReachNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop puts "copy" first (sharing is limited there), mobile puts "send"
/// first; the filled button marks the primary action on each.
class _ActionButton extends StatelessWidget {
  final bool filled;
  final IconData icon;
  final String label;
  final void Function(BuildContext buttonContext) onPressed;

  const _ActionButton({
    super.key,
    required this.filled,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => filled
          ? FilledButton.icon(
              onPressed: () => onPressed(buttonContext),
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () => onPressed(buttonContext),
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }
}
