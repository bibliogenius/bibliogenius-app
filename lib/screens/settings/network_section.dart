import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import '../../widgets/peer_book_cover_cache_manager.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../providers/hub_directory_provider.dart';
import '../../services/auth_service.dart';
import '../../services/ffi_service.dart';
import 'settings_scope.dart';

/// Network accordion (local + remote reachability + public directory)
class NetworkSettingsSection extends StatelessWidget {
  const NetworkSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [
      'settings_network_title',
      'settings_remote_reachable',
      'settings_remote_reachable_desc',
      'hub_coming_soon_toggle',
      'directory_settings_title',
      'directory_listed_title',
      'peer_view_title',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('network_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.wifi),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'settings_network_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _NetworkSettings(),
                const SizedBox(height: 12),
                const DirectorySettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkSettings extends StatefulWidget {
  const _NetworkSettings();

  @override
  State<_NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<_NetworkSettings> {
  SettingsData get _data => settingsDataOf(context);

  /// Local bump that invalidates the size-indicator FutureBuilder after an
  /// action that changes on-disk usage (cap change triggers a sweep, or
  /// the user hits Clear). Using a Key instead of caching the Future lets
  /// us stay with a StatelessWidget-shaped build while still forcing a
  /// fresh diskSizeBytes() read.
  int _peerCoverSizeNonce = 0;

  @override
  Widget build(BuildContext context) {
    // Rebuild when the relay connects on its own after the page loads.
    watchSettingsData(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    String t(String key) => TranslationService.translate(context, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Explanation card ---
        _buildSharingModesCard(context, t),

        // --- Remote reachability (relay) ---
        Semantics(
          header: true,
          child: Text(
            t('settings_remote_reachable'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: Text(t('settings_remote_reachable')),
                subtitle: Text(t('settings_remote_reachable_desc')),
                value: themeProvider.remoteReachableEnabled,
                onChanged: (value) async {
                  await themeProvider.setRemoteReachableEnabled(value);
                  if (value) {
                    _data.autoConnectRelay(context);
                  }
                },
              ),
              if (themeProvider.remoteReachableEnabled) ...[
                const Divider(height: 1),
                ExpansionTile(
                  leading: const Icon(Icons.tune, size: 20),
                  title: Text(
                    t('settings_remote_reachable_details'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  children: [_buildRelayDetails(context)],
                ),
              ],
            ],
          ),
        ),

        // --- Local network sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_network_local'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        const LocalNetworkCard(),

        // Extended network (public directory) hidden until feature is ready

        // --- Privacy & cache sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_network_privacy'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Consumer<HubDirectoryProvider>(
          builder: (context, dirProvider, _) {
            final isHubActive = dirProvider.config?.isListed ?? false;
            final anyNetworkActive =
                themeProvider.networkEnabled ||
                isHubActive ||
                themeProvider.remoteReachableEnabled;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  if (anyNetworkActive) ...[
                    // Mirror of what actually leaves the device. Placed first:
                    // the toggles below are easier to arbitrate once you have
                    // seen the payload they govern.
                    ListTile(
                      leading: const Icon(Icons.preview_outlined),
                      title: Text(t('peer_view_title')),
                      subtitle: Text(t('peer_view_entry_desc')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/peer-view'),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.cloud_off),
                      title: Text(t('peer_offline_caching')),
                      subtitle: Text(t('peer_offline_caching_desc')),
                      value: themeProvider.peerOfflineCachingEnabled,
                      onChanged: (value) =>
                          themeProvider.setPeerOfflineCachingEnabled(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.share),
                      title: Text(t('allow_library_caching')),
                      subtitle: Text(t('allow_library_caching_desc')),
                      value: themeProvider.allowLibraryCaching,
                      onChanged: (value) =>
                          themeProvider.setAllowLibraryCaching(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user),
                      title: Text(t('connection_validation')),
                      subtitle: Text(t('connection_validation_desc')),
                      value: themeProvider.connectionValidationEnabled,
                      onChanged: (value) =>
                          themeProvider.setConnectionValidationEnabled(
                            value,
                            apiService: context.read<ApiService>(),
                          ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(
                        themeProvider.showViewCount
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      title: Text(t('show_view_count')),
                      subtitle: Text(t('show_view_count_desc')),
                      value: themeProvider.showViewCount,
                      onChanged: (value) =>
                          themeProvider.setShowViewCount(value),
                    ),
                  ],
                  if (!anyNetworkActive)
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: Colors.grey[400],
                      ),
                      title: Text(
                        t('settings_network_enable_first'),
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        // --- Peer book covers sub-group ---
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            t('settings_peer_covers_section'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        _buildPeerCoverCoversCard(context, themeProvider, t),
      ],
    );
  }

  Widget _buildPeerCoverCoversCard(
    BuildContext context,
    ThemeProvider themeProvider,
    String Function(String) t,
  ) {
    final theme = Theme.of(context);
    final capMb = themeProvider.peerCoverCacheCapMb;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: Text(t('peer_cover_display_enabled')),
            subtitle: Text(t('peer_cover_display_enabled_desc')),
            value: themeProvider.peerCoverDisplayEnabled,
            onChanged: (value) =>
                themeProvider.setPeerCoverDisplayEnabled(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(t('peer_cover_cache_cap')),
            subtitle: Text(t('peer_cover_cache_cap_desc')),
            trailing: DropdownButton<int>(
              value: capMb,
              // Announce the currently-selected cap to screen readers on
              // focus, otherwise the raw "100 MB" label gives no context.
              items: ThemeProvider.peerCoverCacheCapChoicesMb
                  .map(
                    (mb) =>
                        DropdownMenuItem<int>(value: mb, child: Text('$mb MB')),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await themeProvider.setPeerCoverCacheCapMb(value);
                // Setter runs the disk sweep; our indicator needs a fresh
                // read so the displayed usage reflects any purge.
                if (mounted) {
                  setState(() => _peerCoverSizeNonce++);
                }
              },
            ),
          ),
          const Divider(height: 1),
          FutureBuilder<int>(
            key: ValueKey(_peerCoverSizeNonce),
            future: PeerBookCoverCacheManager.diskSizeBytes(),
            builder: (context, snapshot) {
              final usedMb = snapshot.hasData
                  ? (snapshot.data! / (1024 * 1024)).toStringAsFixed(1)
                  : '...';
              final usageText = TranslationService.translate(
                context,
                'peer_cover_cache_usage',
                params: {'used': usedMb, 'cap': '$capMb'},
              );
              return ListTile(
                leading: const Icon(Icons.data_usage_outlined),
                title: Text(t('peer_cover_cache_usage_title')),
                subtitle: Text(usageText),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: t('peer_cover_cache_refresh'),
                  onPressed: () => setState(() => _peerCoverSizeNonce++),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(
              t('peer_cover_cache_clear'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmClearPeerCoverCache(t),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearPeerCoverCache(String Function(String) t) async {
    // Capture the messenger before any await so the post-clear snackbar
    // is routed to the right Scaffold even if the user navigates away.
    final messenger = ScaffoldMessenger.of(context);
    final confirmLabel = t('peer_cover_cache_clear_done');
    final confirmed = await confirmDestructiveAction(
      context,
      titleKey: 'peer_cover_cache_clear_title',
      titleFallback: 'Clear peer cover cache?',
      bodyKey: 'peer_cover_cache_clear_body',
      bodyFallback:
          'This deletes covers downloaded from peer libraries. '
          'Your own library covers are not affected.',
      actionKey: 'peer_cover_cache_clear_action',
      actionFallback: 'Clear',
    );
    if (!confirmed) return;
    await PeerBookCoverCacheManager.clearAll();
    if (!mounted) return;
    setState(() => _peerCoverSizeNonce++);
    messenger.showSnackBar(
      SnackBar(
        content: Text(confirmLabel),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSharingModesCard(
    BuildContext context,
    String Function(String) t,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('settings_sharing_modes_title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildModeRow(
              context,
              Icons.link,
              t('settings_mode_invite_title'),
              t('settings_mode_invite_desc'),
            ),
            const SizedBox(height: 10),
            _buildModeRow(
              context,
              Icons.wifi,
              t('settings_mode_wifi_title'),
              t('settings_mode_wifi_desc'),
            ),
            const SizedBox(height: 10),
            _buildModeRow(
              context,
              Icons.public,
              t('settings_mode_directory_title'),
              t('settings_mode_directory_desc'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeRow(
    BuildContext context,
    IconData icon,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall,
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' - $desc'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Relay technical details shown inside the accordion.
  Widget _buildRelayDetails(BuildContext context) {
    final api = Provider.of<ApiService>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: _data.relayConnected ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                _data.relayConnected
                    ? (TranslationService.translate(
                            context,
                            'relay_connected',
                          ) ??
                          'Connected')
                    : (TranslationService.translate(
                            context,
                            'relay_disconnected',
                          ) ??
                          'Not connected'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Hub URL is only editable in debug builds to prevent
          // token/cache invalidation cascades when switching hubs.
          if (!kReleaseMode)
            TextField(
              controller: _data.relayUrlController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'relay_url_label') ??
                    'Hub URL',
                hintText: ApiService.hubUrl,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              enabled: !_data.relayLoading,
            ),
          if (_data.relayMailboxUuid != null) ...[
            const SizedBox(height: 6),
            Text(
              'Mailbox: ${_data.relayMailboxUuid!.substring(0, 8)}...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _data.relayConnected
                ? OutlinedButton.icon(
                    onPressed: _data.relayLoading
                        ? null
                        : () async {
                            final confirmed = await confirmDestructiveAction(
                              context,
                              titleKey: 'confirm_remote_disconnect_title',
                              titleFallback: 'Disconnect remote server?',
                              bodyKey: 'confirm_remote_disconnect_body',
                              bodyFallback:
                                  'Your invited contacts will no longer reach you outside your local network.',
                              actionKey: 'confirm_remote_disconnect_action',
                              actionFallback: 'Disconnect',
                            );
                            if (!confirmed || !context.mounted) return;
                            // Taken before the wait: the section may be gone
                            // by the time the hub answers.
                            final messenger = ScaffoldMessenger.of(context);
                            final error = await _data.disconnectRelay(api);
                            if (error != null) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                            }
                          },
                    icon: _data.relayLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_off),
                    label: Text(
                      TranslationService.translate(
                            context,
                            'relay_disconnect',
                          ) ??
                          'Disconnect',
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _data.relayLoading
                        ? null
                        : () async {
                            final url = kReleaseMode
                                ? ApiService.hubUrl
                                : _data.relayUrlController.text.trim();
                            if (url.isEmpty) return;

                            // Taken before the wait: the section may be gone
                            // by the time the hub answers.
                            final messenger = ScaffoldMessenger.of(context);
                            final connected =
                                TranslationService.translate(
                                  context,
                                  'relay_connected',
                                ) ??
                                'Connected';
                            final error = await _data.connectRelay(
                              api,
                              context.read<HubDirectoryProvider>(),
                              url,
                            );
                            messenger.showSnackBar(
                              SnackBar(content: Text(error ?? connected)),
                            );
                          },
                    icon: _data.relayLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      TranslationService.translate(context, 'relay_connect') ??
                          'Connect',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The local-network (Wi-Fi/mDNS) toggle card. Self-contained (wraps its own
/// [Consumer]) so it renders both inside the Network accordion and inside the
/// springboard "Partager sur mon réseau Wi-Fi" bottom sheet.
class LocalNetworkCard extends StatelessWidget {
  const LocalNetworkCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        String t(String key) => TranslationService.translate(context, key);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.wifi),
                title: Text(t('settings_network_discovery')),
                subtitle: Text(t('settings_network_discovery_desc')),
                value: themeProvider.networkEnabled,
                onChanged: (value) => themeProvider.setNetworkEnabled(value),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(t('settings_reshow_invite_banner')),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('invite_banner_dismissed');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t('settings_reshow_invite_banner_done')),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class DirectorySettings extends StatefulWidget {
  const DirectorySettings({super.key, this.showPeerViewLink = false});

  /// Adds the "what another library receives" shortcut at the bottom of the
  /// card. Set on the standalone capability sheet, where the user is deciding
  /// whether to make themselves visible and has nothing else on screen; left
  /// off inside the Network accordion, which already carries the same shortcut
  /// in its privacy sub-group.
  final bool showPeerViewLink;

  @override
  State<DirectorySettings> createState() => _DirectorySettingsState();
}

class _DirectorySettingsState extends State<DirectorySettings> {
  SettingsData get _data => settingsDataOf(context);

  @override
  Widget build(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, dirProvider, _) {
        final config = dirProvider.config;
        final isListed = config?.isListed ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(
                      context,
                      'directory_settings_title',
                    ) ??
                    'Public Directory',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  // Top-level toggle: enable the hub online features.
                  // Browsing the directory is always available (ADR-015 public
                  // endpoint); this toggle gates the bidirectional features:
                  // X25519 key publishing, real-time nudges, and access to
                  // the sub-toggles (isListed, contact, website).
                  SwitchListTile(
                    secondary: const Icon(Icons.explore),
                    title: Text(
                      TranslationService.translate(
                            context,
                            'hub_coming_soon_toggle',
                          ) ??
                          'Public directory',
                    ),
                    subtitle: Text(
                      TranslationService.translate(
                            context,
                            'hub_coming_soon_desc',
                          ) ??
                          'Browse and follow other public libraries',
                    ),
                    value: dirProvider.isHubEnabled,
                    onChanged: (value) async {
                      await dirProvider.setHubEnabled(value);
                      if (value) {
                        dirProvider.initAndSyncCatalog();
                      }
                    },
                  ),

                  if (dirProvider.isHubEnabled) ...[
                    const Divider(height: 1),
                    // Sub-toggle: opt-in to be listed (so others can find you)
                    SwitchListTile(
                      secondary: const Icon(Icons.public),
                      title: Text(
                        TranslationService.translate(
                              context,
                              'directory_listed_title',
                            ) ??
                            'Appear in the public directory',
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                              context,
                              'directory_listed_desc',
                            ) ??
                            'Other libraries can discover and follow you',
                      ),
                      value: isListed,
                      onChanged: dirProvider.configLoading
                          ? null
                          : (value) => _toggleDirectoryListing(
                              context,
                              dirProvider,
                              value,
                            ),
                    ),

                    if (isListed) ...[
                      const Divider(height: 1),
                      // Advanced settings accordion
                      ExpansionTile(
                        leading: const Icon(Icons.tune),
                        title: Text(
                          TranslationService.translate(
                                context,
                                'directory_advanced_settings',
                              ) ??
                              'Advanced settings',
                        ),
                        children: [
                          // Requires approval toggle: new followers need manual
                          // approval before reading the catalog. Hub honors this
                          // in DirectoryService::follow() (pending vs active).
                          SwitchListTile(
                            secondary: const Icon(Icons.how_to_reg),
                            title: Text(
                              TranslationService.translate(
                                    context,
                                    'directory_requires_approval_title',
                                  ) ??
                                  'Require approval for followers',
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                    context,
                                    'directory_requires_approval_desc',
                                  ) ??
                                  'New followers need your approval before accessing your catalog',
                            ),
                            value: config?.requiresApproval ?? false,
                            onChanged: dirProvider.configLoading
                                ? null
                                : (value) => _updateDirectoryConfig(
                                    context,
                                    dirProvider,
                                    requiresApproval: value,
                                  ),
                          ),
                          // Allow borrowing toggle: hub-mediated loan requests.
                          // Enforced server-side in DirectoryService::createBorrowRequest().
                          SwitchListTile(
                            secondary: const Icon(Icons.menu_book_outlined),
                            title: Text(
                              TranslationService.translate(
                                    context,
                                    'hub_allow_borrowing',
                                  ) ??
                                  'Allow borrowing requests',
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                    context,
                                    'hub_allow_borrowing_desc',
                                  ) ??
                                  'Let your followers request to borrow your books via the hub',
                            ),
                            value: config?.allowBorrowing ?? false,
                            onChanged: dirProvider.configLoading
                                ? null
                                : (value) => _updateDirectoryConfig(
                                    context,
                                    dirProvider,
                                    allowBorrowing: value,
                                  ),
                          ),
                          // accept_from selector removed (non-functional)
                        ],
                      ),
                      // The contact card moved to its own "My contact
                      // details" section: it is a library attribute, not a
                      // directory one. Only the public website stays here.
                      // Website (optional, public)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: TextField(
                          controller: _data.hubWebsiteController,
                          decoration: InputDecoration(
                            labelText:
                                TranslationService.translate(
                                  context,
                                  'hub_website_label',
                                ) ??
                                'Website (optional)',
                            hintText: 'https://...',
                            prefixIcon: const Icon(Icons.language),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          onChanged: (value) => dirProvider.setWebsite(value),
                        ),
                      ),
                    ],
                  ], // if (dirProvider.isHubEnabled)
                  // Pre-flight: what actually leaves the library. Offered in
                  // every hub state, since the question ("what would I be
                  // exposing?") comes up before the toggles, not after.
                  if (widget.showPeerViewLink) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.preview_outlined),
                      title: Text(
                        TranslationService.translate(
                          context,
                          'peer_view_title',
                        ),
                      ),
                      subtitle: Text(
                        TranslationService.translate(
                          context,
                          isListed
                              ? 'peer_view_entry_listed_desc'
                              : 'peer_view_entry_preflight_desc',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Resolve the router before popping: after the sheet
                        // closes this element is on its way out and can no
                        // longer look up an inherited widget.
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.push('/peer-view');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleDirectoryListing(
    BuildContext context,
    HubDirectoryProvider dirProvider,
    bool newValue,
  ) async {
    if (!newValue) {
      final confirmed = await confirmDestructiveAction(
        context,
        titleKey: 'confirm_directory_unlist_title',
        titleFallback: 'Leave the public directory?',
        bodyKey: 'confirm_directory_unlist_body',
        bodyFallback:
            'Other libraries will no longer be able to discover you. Existing followers stay active.',
        actionKey: 'confirm_directory_unlist_action',
        actionFallback: 'Leave directory',
      );
      if (!confirmed) return;
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final libraryName = themeProvider.libraryName;

    final config = dirProvider.config;
    // Use existing node_id, or fall back to the stable library UUID (first registration).
    final nodeId = config?.nodeId ?? await authService.getOrCreateLibraryUuid();

    final ffi = FfiService();
    final bookCount = await ffi.countBooks();

    // Fetch local x25519 public key for E2EE contact sharing
    String? x25519PublicKey;
    try {
      x25519PublicKey = await ffi.getLocalX25519PublicKey();
    } catch (_) {}

    final website = dirProvider.websiteUrl.isNotEmpty
        ? dirProvider.websiteUrl
        : null;

    final ok = await dirProvider.register(
      nodeId: nodeId,
      displayName: libraryName,
      bookCount: bookCount,
      isListed: newValue,
      acceptFrom: config?.acceptFrom ?? 'everyone',
      locationCountry: themeProvider.country,
      x25519PublicKey: x25519PublicKey,
      website: website,
    );

    if (ok && !newValue) {
      // Leaving the directory withdraws the city with it. The register call
      // above already sends location_city_id null (the Rust serializer always
      // emits the field), but without dropping the consent the next cold
      // start would re-assert the city through ensureRelayPublished and
      // quietly republish it. The local value stays on the device.
      await dirProvider.setShareCity(false);
    }

    if (ok && newValue) {
      // Push the full ISBN catalog to the hub after listing.
      await dirProvider.syncCatalog();

      // Auto-enable caching when activating hub sharing
      if (!themeProvider.peerOfflineCachingEnabled) {
        themeProvider.setPeerOfflineCachingEnabled(true);
      }
      if (!themeProvider.allowLibraryCaching) {
        themeProvider.setAllowLibraryCaching(true);
      }
    }

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dirProvider.configError ??
                (TranslationService.translate(context, 'error_network') ??
                    'Network error'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _updateDirectoryConfig(
    BuildContext context,
    HubDirectoryProvider dirProvider, {
    bool? requiresApproval,
    String? acceptFrom,
    bool? allowBorrowing,
  }) async {
    final config = dirProvider.config;
    if (config == null) return;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final libraryName = themeProvider.libraryName;

    final ffi = FfiService();
    final bookCount = await ffi.countBooks();

    String? x25519PublicKey;
    try {
      x25519PublicKey = await ffi.getLocalX25519PublicKey();
    } catch (_) {}

    final website = dirProvider.websiteUrl.isNotEmpty
        ? dirProvider.websiteUrl
        : null;

    final ok = await dirProvider.register(
      nodeId: config.nodeId,
      displayName: libraryName,
      bookCount: bookCount,
      requiresApproval: requiresApproval,
      acceptFrom: acceptFrom ?? config.acceptFrom,
      allowBorrowing: allowBorrowing,
      locationCountry: themeProvider.country,
      x25519PublicKey: x25519PublicKey,
      website: website,
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dirProvider.configError ??
                (TranslationService.translate(context, 'error_network') ??
                    'Network error'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String titleKey,
  required String titleFallback,
  required String bodyKey,
  required String bodyFallback,
  required String actionKey,
  required String actionFallback,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(
          TranslationService.translate(dialogContext, titleKey) ??
              titleFallback,
        ),
        content: Text(
          TranslationService.translate(dialogContext, bodyKey) ?? bodyFallback,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              TranslationService.translate(dialogContext, 'cancel') ?? 'Cancel',
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              TranslationService.translate(dialogContext, actionKey) ??
                  actionFallback,
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
