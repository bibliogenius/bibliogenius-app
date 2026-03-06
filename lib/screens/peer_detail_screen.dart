import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/hub_directory.dart';
import '../models/library_relation.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';

/// Detail screen for a library peer / followed library.
class PeerDetailScreen extends StatefulWidget {
  final LibraryRelation relation;

  const PeerDetailScreen({super.key, required this.relation});

  @override
  State<PeerDetailScreen> createState() => _PeerDetailScreenState();
}

class _PeerDetailScreenState extends State<PeerDetailScreen> {
  late LibraryRelation _relation;
  String? _decryptedContact;
  HubProfile? _hubProfile;

  @override
  void initState() {
    super.initState();
    _relation = widget.relation;
    _loadHubInfo();
  }

  Future<void> _loadHubInfo() async {
    final provider = context.read<HubDirectoryProvider>();
    if (!provider.isHubEnabled) return;

    // Decrypt contact from follow relationship
    if (_relation.isFollowing && !_relation.followPending) {
      final follow = provider.followFor(_relation.nodeId);
      final blob = follow?.encryptedContact;
      if (blob != null && blob.isNotEmpty) {
        final plaintext = await provider.openContact(blob);
        if (mounted && plaintext != null) {
          setState(() => _decryptedContact = plaintext);
        }
      }
    }

    // Fetch hub profile for website
    try {
      final frbProfile =
          await FfiService().hubDirectoryGetProfile(_relation.nodeId);
      if (mounted && frbProfile != null) {
        setState(() => _hubProfile = HubProfile.fromFrb(frbProfile));
      }
    } catch (_) {}
  }

  Future<void> _editCaption() async {
    final api = context.read<ApiService>();
    final controller = TextEditingController(text: _relation.caption ?? '');
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(ctx, 'peer_edit_caption'),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: TranslationService.translate(
              ctx,
              'peer_caption_label',
            ),
            hintText: TranslationService.translate(
              ctx,
              'peer_caption_hint',
            ),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          if (_relation.hasCaption)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(
                TranslationService.translate(ctx, 'remove'),
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(TranslationService.translate(ctx, 'save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newCaption == null) return; // Dialog dismissed

    final peer = _relation.peer;
    if (peer != null) {
      await api.updatePeerDisplayName(peer.id, newCaption);
    }

    if (!mounted) return;
    // Reload to get updated peer data
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        newCaption.isEmpty
            ? TranslationService.translate(context, 'peer_caption_removed')
            : TranslationService.translate(context, 'peer_caption_saved'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final peer = _relation.peer;

    // Avatar color encodes connection type
    final Color avatarColor;
    final IconData avatarIcon;
    if (_relation.isPeer && _relation.isFollowing) {
      avatarColor = Colors.teal;
      avatarIcon = Icons.wifi;
    } else if (_relation.isPeer) {
      avatarColor = Colors.blue;
      avatarIcon = Icons.wifi;
    } else {
      avatarColor = Colors.deepPurple;
      avatarIcon = Icons.library_books;
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: TranslationService.translate(
              context,
              'peer_edit_caption',
            ),
            onPressed: _editCaption,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Identity card ---
          Center(
            child: Semantics(
              image: true,
              label: _relation.name,
              child: CircleAvatar(
                radius: 48,
                backgroundColor: avatarColor,
                child: Icon(avatarIcon, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Center(
            child: Text(
              _relation.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Caption (user-defined label)
          if (_relation.hasCaption)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _relation.caption!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 8),

          // Node ID (truncated, copiable)
          Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: _relation.nodeId),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(context, 'copied'),
                      ),
                    ),
                  );
                },
                child: Semantics(
                  button: true,
                  label:
                      '${TranslationService.translate(context, 'peer_node_id')}: ${_relation.nodeId}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        size: 14,
                        color: cs.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _relation.nodeId.length > 16
                            ? '${_relation.nodeId.substring(0, 8)}...${_relation.nodeId.substring(_relation.nodeId.length - 8)}'
                            : _relation.nodeId,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.copy,
                        size: 12,
                        color: cs.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Connection chips
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                if (_relation.isPeer)
                  Chip(
                    avatar: const Icon(Icons.wifi, size: 16),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'lib_connection_peer',
                      ),
                    ),
                  ),
                if (_relation.isFollowing)
                  Chip(
                    avatar: Icon(
                      _relation.followPending
                          ? Icons.pending
                          : Icons.bookmark,
                      size: 16,
                    ),
                    label: Text(
                      _relation.followPending
                          ? TranslationService.translate(
                              context, 'lib_follow_pending')
                          : TranslationService.translate(
                              context, 'lib_follow_active'),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // --- Connection info card ---
          _buildInfoCard(theme, cs, peer),

          const SizedBox(height: 32),

          // --- Action buttons ---
          _buildActionButtons(theme, cs, peer),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, ColorScheme cs, dynamic peer) {
    final hasWebsite = _hubProfile?.website != null &&
        _hubProfile!.website!.isNotEmpty;
    final hasContact = _decryptedContact != null &&
        _decryptedContact!.isNotEmpty;
    final hasE2ee = peer != null && peer.keyExchangeDone;
    final hasLastSeen = peer?.lastSeen != null;
    final hasRelay = peer != null && peer.hasRelayCredentials;

    if (!hasWebsite && !hasContact && !hasE2ee && !hasLastSeen && !hasRelay) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, 'peer_connection_info'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // E2EE status (only shown when active)
            if (hasE2ee)
              _infoRow(
                icon: Icons.lock,
                iconColor: Colors.green,
                label: TranslationService.translate(
                    context, 'peer_e2ee_status'),
                value: TranslationService.translate(
                    context, 'peer_e2ee_active'),
                theme: theme,
              ),

            // Last seen
            if (hasLastSeen) ...[
              if (hasE2ee) const SizedBox(height: 12),
              _infoRow(
                icon: Icons.access_time,
                iconColor: cs.outline,
                label: TranslationService.translate(
                    context, 'peer_last_seen'),
                value: peer!.lastSeen!,
                theme: theme,
              ),
            ],

            // Relay
            if (hasRelay) ...[
              const SizedBox(height: 12),
              _infoRow(
                icon: Icons.cloud,
                iconColor: Colors.blue,
                label: TranslationService.translate(
                    context, 'peer_has_relay'),
                theme: theme,
              ),
            ],

            // Website
            if (hasWebsite) ...[
              const SizedBox(height: 12),
              _buildWebsiteRow(_hubProfile!.website!, cs, theme),
            ],

            // Encrypted contact
            if (hasContact) ...[
              const SizedBox(height: 12),
              _infoRow(
                icon: Icons.lock_outlined,
                iconColor: cs.primary,
                label: TranslationService.translate(
                    context, 'hub_contact_info_title'),
                value: _decryptedContact!,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: value != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ],
                )
              : Text(label, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildWebsiteRow(String url, ColorScheme cs, ThemeData theme) {
    var s = url.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.host.contains('.')) return const SizedBox.shrink();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.language, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                uri.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
      ThemeData theme, ColorScheme cs, dynamic peer) {
    final buttons = <Widget>[];

    // Browse catalog
    if (_relation.canBrowseCatalog) {
      if (_relation.isPeer && peer?.url != null) {
        buttons.add(
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.menu_book, size: 18),
              label: Text(
                TranslationService.translate(context, 'browse_library'),
              ),
              onPressed: () => context.push(
                '/peers/${peer!.id}/books',
                extra: {
                  'id': peer.id,
                  'name': _relation.name,
                  'url': peer.url,
                  'hasRelayCredentials': peer.hasRelayCredentials,
                  'nodeId': _relation.nodeId,
                },
              ),
            ),
          ),
        );
      } else if (_relation.isFollowing && _relation.follow!.isActive) {
        buttons.add(
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.menu_book, size: 18),
              label: Text(
                TranslationService.translate(context, 'browse_library'),
              ),
              onPressed: () => context.push(
                '/directory/${Uri.encodeComponent(_relation.nodeId)}',
              ),
            ),
          ),
        );
      }
    }

    // Sync (peers only)
    if (_relation.isPeer && peer?.url != null) {
      buttons.add(
        Consumer<ApiService>(
          builder: (context, api, _) => SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sync, size: 18),
              label: Text(
                TranslationService.translate(context, 'tooltip_sync'),
              ),
              onPressed: () async {
                await api.syncPeer(peer!.url!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      TranslationService.translate(
                          context, 'sync_started'),
                    ),
                  ));
                }
              },
            ),
          ),
        ),
      );
    }

    // Unfollow
    if (_relation.isFollowing && !_relation.followPending) {
      buttons.add(
        Consumer<HubDirectoryProvider>(
          builder: (context, dirProvider, _) => SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.bookmark_remove,
                  size: 18, color: cs.error),
              label: Text(
                TranslationService.translate(context, 'lib_unfollow'),
                style: TextStyle(color: cs.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
              ),
              onPressed: () async {
                await dirProvider.unfollow(_relation.nodeId);
                if (context.mounted) context.pop();
              },
            ),
          ),
        ),
      );
    }

    // Disconnect peer
    if (_relation.isPeer) {
      buttons.add(
        Consumer<ApiService>(
          builder: (context, api, _) => SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.link_off, size: 18, color: cs.error),
              label: Text(
                TranslationService.translate(context, 'delete'),
                style: TextStyle(color: cs.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      TranslationService.translate(
                        ctx,
                        'delete_contact_title',
                      ),
                    ),
                    content: Text(
                      '${TranslationService.translate(ctx, 'confirm_delete')} '
                      '${_relation.name}?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          TranslationService.translate(ctx, 'cancel'),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          TranslationService.translate(
                            ctx,
                            'delete_contact_btn',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  api.deletePeer(peer!.id);
                  if (context.mounted) context.pop('deleted');
                }
              },
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          buttons[i],
          if (i < buttons.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}
