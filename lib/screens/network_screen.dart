import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/invite_share_sheet.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/shimmer_loading.dart';
import '../utils/invite_payload.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../models/avatar_config.dart';
import '../models/network_member.dart';
import '../models/library_relation.dart';
import '../data/repositories/contact_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/mdns_service.dart';
import '../providers/flash_message_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/pending_peers_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../models/hub_directory.dart';

/// Unified screen displaying "Mon reseau" and "Decouvrir" tabs
class NetworkScreen extends StatefulWidget {
  final int initialIndex;

  const NetworkScreen({super.key, this.initialIndex = 0});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen>
    with SingleTickerProviderStateMixin {
  TabController? _mainTabController;
  int _tabCount = 0;
  final GlobalKey<_MyNetworkViewState> _myNetworkKey =
      GlobalKey<_MyNetworkViewState>();

  @override
  void initState() {
    super.initState();
  }

  void _ensureTabController(int count) {
    if (count == _tabCount && _mainTabController != null) return;
    _mainTabController?.removeListener(_onTabChanged);
    _mainTabController?.dispose();
    _tabCount = count;
    _mainTabController = TabController(
      length: count,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, count - 1),
    );
    _mainTabController!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    setState(() {});
    // Reload "Mon réseau" data when switching back to tab 0
    if (_mainTabController!.index == 0 && !_mainTabController!.indexIsChanging) {
      _myNetworkKey.currentState?.reloadMembers();
    }
  }

  @override
  void dispose() {
    _mainTabController?.removeListener(_onTabChanged);
    _mainTabController?.dispose();
    super.dispose();
  }

  /// Shows the modal bottom sheet for adding a new connection
  void _showAddConnectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.teal.withValues(alpha: 0.2)
                            : Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.people_alt, color: Colors.teal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      TranslationService.translate(context, 'add_connection_title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Actions grid
                Row(
                  children: [
                    Expanded(
                      child: _ConnectionActionCard(
                        key: const Key('actionEnterManually'),
                        icon: Icons.edit,
                        color: Colors.orange,
                        label: TranslationService.translate(context, 'enter_manually'),
                        isDark: isDark,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final result = await context.push('/contacts/add');
                          if (result == true) {
                            _myNetworkKey.currentState?.reloadMembers();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ConnectionActionCard(
                        key: const Key('actionScanQr'),
                        icon: Icons.qr_code_scanner,
                        color: Colors.blue,
                        label: TranslationService.translate(context, 'scan_qr_code'),
                        isDark: isDark,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final result = await context.push('/scan-qr');
                          if (result == true) {
                            _myNetworkKey.currentState?.reloadMembers();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ConnectionActionCard(
                        key: const Key('actionShowMyCode'),
                        icon: Icons.qr_code,
                        color: Colors.purple,
                        label: TranslationService.translate(context, 'show_my_code'),
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showGeneralDialog(
                            context: context,
                            barrierDismissible: true,
                            barrierLabel: MaterialLocalizations.of(context)
                                .modalBarrierDismissLabel,
                            transitionDuration:
                                const Duration(milliseconds: 300),
                            pageBuilder: (dialogContext, _, _) => Scaffold(
                              key: const Key('showMyCodeDialog'),
                              appBar: AppBar(
                                title: Text(
                                  TranslationService.translate(
                                      context, 'show_my_code'),
                                ),
                                leading: IconButton(
                                  key: const Key('closeShowMyCode'),
                                  icon: const Icon(Icons.close),
                                  tooltip: TranslationService.translate(
                                      context, 'close'),
                                  onPressed: () =>
                                      Navigator.pop(dialogContext),
                                ),
                              ),
                              body: const SafeArea(
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.all(24),
                                  child: ShareContactView(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Share invite link button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('actionShareInviteLink'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      shareInviteLinkDirect(context);
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(
                      TranslationService.translate(context, 'share_invite_link'),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;
    // Discover tab is always visible: browsing the public directory does not
    // require the user to opt in or publish their library (ADR-015 §GET
    // /api/directory is a public endpoint). Opting in is offered via a CTA
    // banner inside the Discover tab itself.
    const tabCount = 2;
    _ensureTabController(tabCount);

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'nav_network'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
        actions: [
          // Help button: content switches based on active tab.
          if ((_mainTabController?.index ?? 0) == 1)
            // Discover tab
            const ContextualHelpIconButton(
              titleKey: 'help_ctx_discover_title',
              contentKey: 'help_ctx_discover_content',
              tips: [
                HelpTip(
                  icon: Icons.swap_horiz,
                  color: Colors.deepPurple,
                  titleKey: 'help_ctx_discover_tip_unidirectional',
                  descriptionKey: 'help_ctx_discover_tip_unidirectional_desc',
                ),
                HelpTip(
                  icon: Icons.library_books,
                  color: Colors.green,
                  titleKey: 'help_ctx_discover_tip_follow',
                  descriptionKey: 'help_ctx_discover_tip_follow_desc',
                ),
              ],
            )
          else
            // My Network tab (default)
            const ContextualHelpIconButton(
              titleKey: 'help_ctx_network_title',
              contentKey: 'help_ctx_network_content',
              tips: [
                HelpTip(
                  icon: Icons.person_add,
                  color: Colors.blue,
                  titleKey: 'help_ctx_network_tip_add',
                  descriptionKey: 'help_ctx_network_tip_add_desc',
                ),
                HelpTip(
                  icon: Icons.library_books,
                  color: Colors.green,
                  titleKey: 'help_ctx_network_tip_browse',
                  descriptionKey: 'help_ctx_network_tip_browse_desc',
                ),
                HelpTip(
                  icon: Icons.bookmark_add,
                  color: Colors.orange,
                  titleKey: 'help_ctx_network_tip_request',
                  descriptionKey: 'help_ctx_network_tip_request_desc',
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _mainTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Consumer<HubDirectoryProvider>(
                builder: (context, dirProvider, _) {
                  final count = dirProvider.pendingCount;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        TranslationService.translate(
                          context, 'network_tab_my_network',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Tab(text: TranslationService.translate(context, 'network_tab_discover')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _MyNetworkView(key: _myNetworkKey),
          const _DiscoverView(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
              key: const Key('networkAddFab'),
              heroTag: 'network_add_fab',
              onPressed: () => _showAddConnectionSheet(context),
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// Unified "Mon reseau" view: borrowers + P2P peers + hub follows + mDNS
class _MyNetworkView extends StatefulWidget {
  const _MyNetworkView({super.key});

  @override
  State<_MyNetworkView> createState() => _MyNetworkViewState();
}

class _MyNetworkViewState extends State<_MyNetworkView> {
  static const _bannerDismissedKey = 'invite_banner_dismissed';

  // Static cache: survives widget recreation during tab navigation
  static List<NetworkMember> _cachedBorrowers = [];
  static List<LibraryRelation> _cachedRelations = [];
  static List<DiscoveredPeer> _cachedLocalPeers = [];

  List<NetworkMember> _borrowers = [];
  List<LibraryRelation> _relations = [];
  List<DiscoveredPeer> _localPeers = [];
  bool _isLoading = true;
  bool _bannerVisible = false;
  DateTime? _lastRefreshTime;
  LibraryFilter _filter = LibraryFilter.all;
  late final HubDirectoryProvider _dirProvider;
  Timer? _mdnsRefreshTimer;
  Timer? _peerSyncTimer;
  // Cached identifiers from saved peers, used to filter mDNS duplicates
  Set<String> _savedUuids = {};
  Set<String> _savedHosts = {};
  // Peers whose relay URL has already been upgraded to LAN this session
  final Set<int> _relayUpgradedPeerIds = {};
  // Peer online status: nodeId -> true (online) / false (unreachable)
  // null (absent) = not yet checked
  final Map<String, bool> _peerOnlineStatus = {};
  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restore from static cache to prevent flicker during tab navigation
    final hasCache = _cachedRelations.isNotEmpty ||
        _cachedBorrowers.isNotEmpty ||
        _cachedLocalPeers.isNotEmpty;
    if (hasCache) {
      _borrowers = List.of(_cachedBorrowers);
      _relations = List.of(_cachedRelations);
      _localPeers = List.of(_cachedLocalPeers);
      _isLoading = false;
    }
    _dirProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    _dirProvider.addListener(_onDirectoryChanged);
    _checkBannerVisibility();
    _loadAll(showLoading: !hasCache);
    // Poll mDNS peers every 3s (discovery is async, no callback available)
    _mdnsRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshLocalPeers(),
    );
    // Periodic peer sync to detect remote disconnections (every 30s)
    _peerSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncAndReload(),
    );
  }

  Future<void> _checkBannerVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_bannerDismissedKey) ?? false;
    if (!dismissed && mounted) {
      setState(() => _bannerVisible = true);
    }
  }

  Future<void> _dismissBanner() async {
    setState(() => _bannerVisible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bannerDismissedKey, true);
  }

  @override
  void dispose() {
    _mdnsRefreshTimer?.cancel();
    _peerSyncTimer?.cancel();
    _searchController.dispose();
    _dirProvider.removeListener(_onDirectoryChanged);
    super.dispose();
  }

  void reloadMembers() => _loadAll();

  /// Reconstruct peersData from the current UI state when getPeers() fails.
  /// Preserves displayed peers instead of showing an empty list.
  List<Map<String, dynamic>> _peersDataFromRelations() {
    return _relations
        .where((r) => r.peer != null)
        .map((r) => <String, dynamic>{
              'id': r.peer!.id,
              'name': r.peer!.name,
              'url': r.peer!.url,
              'library_uuid': r.peer!.libraryUuid,
              'status': r.peer!.status,
              'connection_status':
                  r.peer!.status == 'pending' ? 'pending' : 'accepted',
              'last_seen': r.peer!.lastSeen,
              'key_exchange_done': r.peer!.keyExchangeDone,
              'relay_url':
                  r.peer!.hasRelayCredentials ? 'present' : null,
              'mailbox_id':
                  r.peer!.hasRelayCredentials ? 'present' : null,
              'relay_write_token':
                  r.peer!.hasRelayCredentials ? 'present' : null,
              'display_name': r.peer!.customDisplayName,
            })
        .toList();
  }

  /// Optimistically remove a relation from the list by nodeId.
  void _removeRelation(String nodeId) {
    if (!mounted) return;
    setState(() {
      _relations.removeWhere((r) => r.nodeId == nodeId);
    });
  }

  /// Sync all peers then reload the list unconditionally.
  /// Detects remote disconnections (sync returns 404 -> peer deleted locally).
  /// Used by the periodic background timer.
  Future<void> _syncAndReload() async {
    if (!mounted) return;
    final syncService = Provider.of<SyncService>(context, listen: false);
    await syncService.syncAllPeers();
    if (!mounted) return;
    await _loadAll();
  }

  /// Pull-to-refresh: reload local data immediately (fast), then sync peers
  /// in the background and reload again when sync completes.
  Future<void> _pullToRefresh() async {
    if (!mounted) return;
    // Invalidate hub name cache so loadFollowing re-fetches fresh names
    final dirProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    dirProvider.invalidateNameCache();
    // 1. Reload from local DB/API instantly — the user sees fresh data right away
    await _loadAll();
    if (!mounted) return;
    // 2. Sync peers in background, then reload when done
    final syncService = Provider.of<SyncService>(context, listen: false);
    syncService.syncAllPeers().then((_) {
      if (mounted) {
        _loadAll();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            TranslationService.translate(context, 'sync_completed'),
          ),
          duration: const Duration(seconds: 2),
        ));
      }
    });
  }

  /// Lightweight refresh: re-read MdnsService.peers without re-fetching API data.
  /// Also cross-references mDNS names with saved peers for instant name updates.
  void _refreshLocalPeers() {
    if (!mounted) return;
    final allMdns = MdnsService.peers;
    final localPeers = allMdns
        .where((p) {
          if (p.libraryId != null && _savedUuids.contains(p.libraryId)) {
            return false;
          }
          if (_savedHosts.contains(p.host)) return false;
          return true;
        })
        .toList();

    // Cross-reference mDNS names with saved peers for instant name updates
    bool relationsChanged = false;
    final mdnsNameByHost = <String, String>{};
    final mdnsNameByUuid = <String, String>{};
    for (final mp in allMdns) {
      mdnsNameByHost[mp.host] = mp.name;
      if (mp.libraryId != null) mdnsNameByUuid[mp.libraryId!] = mp.name;
    }
    final updatedRelations = _relations.map((r) {
      final p = r.peer;
      if (p == null) return r;
      String? mdnsName;
      if (p.libraryUuid != null) {
        mdnsName = mdnsNameByUuid[p.libraryUuid];
      }
      if (mdnsName == null && p.url != null) {
        try {
          mdnsName = mdnsNameByHost[Uri.parse(p.url!).host];
        } catch (_) {}
      }
      if (mdnsName != null && mdnsName != p.name && r.name != mdnsName) {
        relationsChanged = true;
        return r.withDisplayName(mdnsName);
      }
      return r;
    }).toList();

    // Upgrade relay peers to LAN when mDNS discovers them on the same WiFi.
    // Build a lookup: mDNS peer by UUID and by name for matching.
    final mdnsByUuid = <String, DiscoveredPeer>{};
    final mdnsByName = <String, DiscoveredPeer>{};
    for (final mp in allMdns) {
      if (mp.libraryId != null) mdnsByUuid[mp.libraryId!] = mp;
      mdnsByName[mp.name] = mp;
    }
    for (final r in _relations) {
      final p = r.peer;
      if (p == null || p.url == null) continue;
      if (_relayUpgradedPeerIds.contains(p.id)) continue;

      DiscoveredPeer? match;
      String? reason;

      if (p.url!.startsWith('relay://')) {
        // Relay peer: match by UUID (strong) then by name (fallback)
        if (p.libraryUuid != null) match = mdnsByUuid[p.libraryUuid];
        match ??= mdnsByName[p.displayName];
        if (match != null) reason = 'relay→LAN';
      } else if (p.libraryUuid != null) {
        // LAN peer: fix port mismatch if UUID matches an mDNS peer
        match = mdnsByUuid[p.libraryUuid];
        if (match != null) {
          final lanUrl = 'http://${match.host}:${match.port}';
          if (lanUrl == p.url) {
            match = null; // Already correct
          } else {
            reason = 'port update';
          }
        }
      }

      if (match != null && reason != null) {
        final lanUrl = 'http://${match.host}:${match.port}';
        _relayUpgradedPeerIds.add(p.id);
        final api = Provider.of<ApiService>(context, listen: false);
        // Verify connectivity before upgrading — stale mDNS entries
        // (peer left WiFi) would otherwise overwrite a working relay URL.
        // Keep the ID in the set on failure to avoid retrying every cycle.
        api.checkPeerConnectivity(lanUrl, timeoutMs: 2000).then((reachable) {
          if (!reachable) {
            debugPrint('mDNS: $reason "${r.name}" → $lanUrl SKIPPED (unreachable)');
            return;
          }
          debugPrint('mDNS: $reason "${r.name}" → $lanUrl');
          api.updatePeerUrl(p.id, lanUrl, libraryUuid: match!.libraryId).then((_) {
            debugPrint('mDNS: $reason persisted for "${r.name}"');
            if (mounted) _loadAll();
          }).catchError((e) {
            debugPrint('mDNS: $reason failed for "${r.name}": $e');
            _relayUpgradedPeerIds.remove(p.id);
          });
        });
      }
    }

    final peersChanged = localPeers.length != _localPeers.length ||
        !_sameHosts(localPeers, _localPeers);

    if (peersChanged || relationsChanged) {
      setState(() {
        _localPeers = localPeers;
        if (relationsChanged) _relations = updatedRelations;
      });
    }
  }

  bool _sameHosts(List<DiscoveredPeer> a, List<DiscoveredPeer> b) {
    if (a.length != b.length) return false;
    final hostsA = a.map((p) => '${p.host}:${p.port}').toSet();
    final hostsB = b.map((p) => '${p.host}:${p.port}').toSet();
    return hostsA.containsAll(hostsB) && hostsB.containsAll(hostsA);
  }

  void _onDirectoryChanged() {
    if (!mounted) return;
    final dirProvider =
        Provider.of<HubDirectoryProvider>(context, listen: false);
    bool changed = false;
    final updated = _relations.map((r) {
      if (r.isFollowing) {
        if (r.isPeer) {
          // Peer+follow: only apply user-custom names, not auto-resolved hub names.
          final customName = dirProvider.customFollowName(r.nodeId);
          if (customName != null && r.name != customName) {
            changed = true;
            return r.withDisplayName(customName);
          }
        } else {
          // Follow-only: hub name is the only source.
          final hubName = dirProvider.displayNameFor(r.nodeId);
          if (hubName != null && r.name != hubName) {
            changed = true;
            return r.withDisplayName(hubName);
          }
        }
      }
      return r;
    }).toList();
    if (changed) setState(() => _relations = updated);
  }

  Future<void> _loadAll({bool showLoading = false}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final contactRepo = Provider.of<ContactRepository>(context, listen: false);
      final dirProvider =
          Provider.of<HubDirectoryProvider>(context, listen: false);

      // Load all data sources concurrently - each isolated so one failure
      // does not prevent the others from loading.
      final libraryId = await authService.getLibraryId();

      List<dynamic> contactsList = [];
      List<dynamic> peersData = [];
      try {
        contactsList = await contactRepo.getContacts(libraryId: libraryId);
      } catch (e) {
        debugPrint('Error loading contacts: $e');
      }

      try {
        final peersRes = await api.getPeers();
        if (peersRes.statusCode == 200) {
          peersData =
              ((peersRes.data as Map<String, dynamic>?)?['data']
                      as List<dynamic>?) ??
                  [];
        } else {
          debugPrint('getPeers returned ${peersRes.statusCode}, preserving existing peers');
          peersData = _peersDataFromRelations();
        }
      } catch (e) {
        debugPrint('Error loading peers: $e');
        peersData = _peersDataFromRelations();
      }

      // Hub: load config, auto-register if needed, push catalog
      try {
        await dirProvider.loadConfig();
        if (!dirProvider.isRegistered) {
          // Auto-register so catalog is always available for known peers
          await dirProvider.ensureRegistered();
        }
        if (dirProvider.isRegistered) {
          final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
          final name = themeProvider.libraryName;
          dirProvider.ensureKeysPublished(name);
          dirProvider.syncCatalogIfDirty();
        }
      } catch (e) { debugPrint('Error loading hub config: $e'); }
      try {
        await dirProvider.loadFollowing();
      } catch (e) { debugPrint('Error loading follows: $e'); }
      dirProvider.loadPendingRequests().catchError(
        (e) => debugPrint('Error loading pending requests: $e'),
      );

      // Borrowers
      final borrowers = contactsList
          .map((c) => NetworkMember.fromContact(c))
          .where((m) => m.type == NetworkMemberType.borrower)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Peers
      final peers = peersData
          .map((j) => NetworkMember.fromPeer(j as Map<String, dynamic>))
          .toList();
      final follows = dirProvider.following;

      // Deduplicate peers by libraryUuid (same device may have multiple
      // entries due to port changes from hot restarts). Keep the most recent.
      final dedupedPeers = <NetworkMember>[];
      final seenUuids = <String, int>{}; // uuid → index in dedupedPeers
      for (final peer in peers) {
        if (peer.libraryUuid != null) {
          final idx = seenUuids[peer.libraryUuid!];
          if (idx != null) {
            // Same UUID already seen — keep the one with higher id (newer)
            if (peer.id > dedupedPeers[idx].id) {
              dedupedPeers[idx] = peer;
            }
            continue;
          }
          seenUuids[peer.libraryUuid!] = dedupedPeers.length;
        }
        dedupedPeers.add(peer);
      }

      // Merge peers + follows by nodeId
      final Map<String, LibraryRelation> map = {};
      for (final peer in dedupedPeers) {
        final nodeId = peer.libraryUuid ?? 'peer_${peer.id}';
        map[nodeId] = LibraryRelation(
          nodeId: nodeId,
          peer: peer,
          hubAvatarConfig: dirProvider.avatarConfigFor(nodeId),
        );
      }
      for (final follow in follows) {
        final nodeId = follow.followedNodeId;
        final existing = map[nodeId];
        if (existing != null) {
          // Peer+follow: peer's own name (from P2P sync) is authoritative.
          // Only override with user-set custom name, not auto-resolved hub name.
          var merged = existing.withFollow(follow);
          final customName = dirProvider.customFollowName(nodeId);
          if (customName != null) {
            merged = merged.withDisplayName(customName);
          }
          map[nodeId] = merged;
        } else {
          // Hub-follow only: hub name is the only source available.
          final hubName = dirProvider.displayNameFor(nodeId);
          map[nodeId] = LibraryRelation(
            nodeId: nodeId,
            displayName: hubName,
            follow: follow,
            hubAvatarConfig: dirProvider.avatarConfigFor(nodeId),
          );
        }
      }

      // Cross-reference mDNS names with saved peers: if an mDNS peer matches
      // a saved peer by host or library_uuid and has a different name, update
      // the displayed name immediately (the sync will persist it later).
      final mdnsPeers = MdnsService.peers;
      final mdnsNameByHost = <String, String>{};
      final mdnsNameByUuid = <String, String>{};
      for (final mp in mdnsPeers) {
        mdnsNameByHost[mp.host] = mp.name;
        if (mp.libraryId != null) {
          mdnsNameByUuid[mp.libraryId!] = mp.name;
        }
      }
      for (final entry in map.entries) {
        final p = entry.value.peer;
        if (p == null) continue;
        String? mdnsName;
        if (p.libraryUuid != null) {
          mdnsName = mdnsNameByUuid[p.libraryUuid];
        }
        if (mdnsName == null && p.url != null) {
          try {
            mdnsName = mdnsNameByHost[Uri.parse(p.url!).host];
          } catch (_) {}
        }
        if (mdnsName != null && mdnsName != p.name) {
          map[entry.key] = entry.value.withDisplayName(mdnsName);
        }
      }

      final relations = map.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Cache saved peer identifiers for the periodic mDNS refresh
      _savedUuids =
          dedupedPeers.map((p) => p.libraryUuid).whereType<String>().toSet();
      _savedHosts = dedupedPeers
          .map((p) {
            if (p.url == null) return null;
            try {
              return Uri.parse(p.url!).host;
            } catch (_) {
              return null;
            }
          })
          .whereType<String>()
          .toSet();

      final localPeers = mdnsPeers
          .where((p) {
            if (p.libraryId != null && _savedUuids.contains(p.libraryId)) {
              return false;
            }
            if (_savedHosts.contains(p.host)) return false;
            return true;
          })
          .toList();

      if (mounted) {
        setState(() {
          _borrowers = borrowers;
          _relations = relations;
          _localPeers = localPeers;
          _isLoading = false;
          _lastRefreshTime = DateTime.now();
        });
        // Update static cache for instant restore on tab switch
        _cachedBorrowers = borrowers;
        _cachedRelations = relations;
        _cachedLocalPeers = localPeers;
        // Check peer connectivity (fire-and-forget, non-blocking)
        _checkPeersConnectivity(relations);
      }
    } catch (e) {
      debugPrint('Error loading network: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Check connectivity for all peers with a URL, in parallel.
  /// Fire-and-forget: updates _peerOnlineStatus as results come in.
  void _checkPeersConnectivity(List<LibraryRelation> relations) {
    final api = Provider.of<ApiService>(context, listen: false);
    final Map<String, bool> immediate = {};
    for (final r in relations) {
      final url = r.peer?.url;
      if (url == null || url.isEmpty) {
        // No URL: not checkable, mark false once so no spinner is shown
        immediate.putIfAbsent(r.nodeId, () => false);
        continue;
      }
      if (url.startsWith('relay://')) {
        // Relay-only: not directly reachable. Mark false so the blueGrey dot
        // (hasRelayCredentials) is shown instead of an indefinite spinner.
        immediate.putIfAbsent(r.nodeId, () => false);
        continue;
      }
      api.checkPeerConnectivity(url).then((online) {
        if (!mounted) return;
        setState(() => _peerOnlineStatus[r.nodeId] = online);
      });
    }
    if (immediate.isNotEmpty) {
      setState(() => _peerOnlineStatus.addAll(immediate));
    }
  }

  bool _matchesSearch(String name) {
    if (_searchQuery.isEmpty) return true;
    return name.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  List<LibraryRelation> get _filteredRelations {
    final byFilter = switch (_filter) {
      LibraryFilter.all => _relations,
      LibraryFilter.nearby => _relations.where((r) => r.isPeer).toList(),
      LibraryFilter.following =>
        _relations.where((r) => r.isFollowing).toList(),
      LibraryFilter.borrowers => <LibraryRelation>[],
    };
    if (_searchQuery.isEmpty) return byFilter;
    return byFilter.where((r) => _matchesSearch(r.name)).toList();
  }

  List<NetworkMember> get _filteredBorrowers {
    final byFilter = switch (_filter) {
      LibraryFilter.all => _borrowers,
      LibraryFilter.borrowers => _borrowers,
      _ => <NetworkMember>[],
    };
    if (_searchQuery.isEmpty) return byFilter;
    return byFilter.where((m) => _matchesSearch(m.displayName)).toList();
  }

  List<DiscoveredPeer> get _visibleLocalPeers {
    final byFilter =
        (_filter == LibraryFilter.all || _filter == LibraryFilter.nearby)
            ? _localPeers
            : <DiscoveredPeer>[];
    if (_searchQuery.isEmpty) return byFilter;
    return byFilter.where((p) => _matchesSearch(p.name)).toList();
  }

  bool get _isEmpty =>
      _filteredRelations.isEmpty &&
      _filteredBorrowers.isEmpty &&
      _visibleLocalPeers.isEmpty;

  Future<void> _deleteContact(NetworkMember member) async {
    final contactRepo =
        Provider.of<ContactRepository>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(ctx, 'delete_contact_title'),
        ),
        content: Text(
          '${TranslationService.translate(ctx, 'confirm_delete')} ${member.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              TranslationService.translate(ctx, 'delete_contact_btn'),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await contactRepo.deleteContact(member.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              TranslationService.translate(context, 'contact_deleted'),
            ),
          ));
          _loadAll();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingProvider = context.watch<PendingPeersProvider>();
    final hubDirProvider = context.watch<HubDirectoryProvider>();
    // Reset filter if hub was disabled while "following" filter was active
    if (!hubDirProvider.isHubEnabled && _filter == LibraryFilter.following) {
      _filter = LibraryFilter.all;
    }
    return Column(
      children: [
        if (pendingProvider.pendingCount > 0)
          _PendingBanner(
            count: pendingProvider.pendingCount,
            onAction: pendingProvider.refresh,
          ),
        // Hub follow requests (only when hub directory is enabled)
        if (hubDirProvider.isHubEnabled &&
            hubDirProvider.pendingRequests.isNotEmpty)
          _HubRequestsSection(
            requests: hubDirProvider.pendingRequests,
            provider: hubDirProvider,
          ),
        // Invite banner
        if (_bannerVisible)
          _InviteBanner(
            onTap: () => shareInviteLinkDirect(context),
            onDismiss: _dismissBanner,
          ),
        // Search bar + Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: _isSearching
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: TranslationService.translate(context, 'search'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: TranslationService.translate(context, 'close'),
                            onPressed: () {
                              setState(() {
                                _isSearching = false;
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, size: 20),
                        tooltip: TranslationService.translate(context, 'search'),
                        onPressed: () => setState(() => _isSearching = true),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildFilterChip(
                        LibraryFilter.all, 'network_filter_all',
                        const Key('netFilterAll'),
                        icon: Icons.people,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        LibraryFilter.nearby, 'lib_filter_nearby',
                        const Key('netFilterNearby'),
                        icon: Icons.near_me,
                      ),
                      if (hubDirProvider.isHubEnabled) ...[
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          LibraryFilter.following, 'lib_filter_following',
                          const Key('netFilterFollowing'),
                          icon: Icons.bookmark,
                        ),
                      ],
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        LibraryFilter.borrowers, 'network_filter_borrowers',
                        const Key('netFilterBorrowers'),
                        icon: Icons.person,
                      ),
                    ],
                  ),
                ),
        ),
        if (_lastRefreshTime != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              _formatLastRefresh(_lastRefreshTime!),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: _isLoading && _relations.isEmpty && _localPeers.isEmpty && _borrowers.isEmpty
              ? const NetworkLoadingSkeleton()
              : RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: _isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [_buildEmptyState(context)],
                        )
                      : ListView(
                          key: const Key('myNetworkList'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            // mDNS peers (not yet saved)
                            if (_visibleLocalPeers.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _sectionHeader(
                                context,
                                TranslationService.translate(
                                  context, 'local_network_title',
                                ),
                                Icons.wifi,
                                subtitle: TranslationService.translate(
                                  context, 'local_network_hint',
                                ),
                                key: const Key('localNetworkSection'),
                              ),
                              ..._visibleLocalPeers.map(_buildLocalPeerTile),
                              if (_filteredRelations.isNotEmpty ||
                                  _filteredBorrowers.isNotEmpty)
                                const Divider(height: 8),
                            ],
                            // Library relations (peers + follows)
                            ..._filteredRelations.map(
                              (r) => _LibraryRelationCard(
                                relation: r,
                                onRefresh: _syncAndReload,
                                onRemoved: _removeRelation,
                                isOnline: _peerOnlineStatus[r.nodeId],
                              ),
                            ),
                            // Borrowers
                            ..._filteredBorrowers.map(_buildBorrowerTile),
                          ],
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    LibraryFilter filter, String labelKey, Key key, {IconData? icon}) {
    final selected = _filter == filter;
    return FilterChip(
      key: key,
      avatar: icon != null
          ? Icon(icon, size: 16, color: selected ? Colors.white : null)
          : null,
      label: Text(TranslationService.translate(context, labelKey)),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
      ),
    );
  }

  String _formatLastRefresh(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return TranslationService.translate(context, 'last_updated_just_now');
    } else if (diff.inHours < 1) {
      return TranslationService.translate(context, 'last_updated_minutes')
          .replaceFirst('%d', '${diff.inMinutes}');
    } else {
      return TranslationService.translate(context, 'last_updated_hours')
          .replaceFirst('%d', '${diff.inHours}');
    }
  }

  Widget _buildBorrowerTile(NetworkMember member) {
    return Semantics(
      button: true,
      label: member.displayName,
      child: Card(
        key: Key('memberTile_${member.id}'),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(
            '/contacts/${member.id}?isNetwork=false',
            extra: member.toContact(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Tooltip(
                  message: TranslationService.translate(
                      context, 'contact_type_borrower'),
                  child: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.person, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    member.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  tooltip: TranslationService.translate(context, 'delete'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                  onPressed: () => _deleteContact(member),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    Key? key,
    String? subtitle,
  }) {
    return Semantics(
      header: true,
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPeerTile(DiscoveredPeer peer) {
    final defaultName = '${peer.host}:${peer.port}';
    final rawName = peer.name;
    // Strip device suffix when a generic default name is shown
    final displayName =
        rawName.contains(' - ') && rawName == defaultName
            ? rawName.split(' - ').first
            : rawName;
    final showSubtitle = peer.deviceName != null && rawName == defaultName;

    return Semantics(
      button: true,
      label: displayName,
      child: Card(
        surfaceTintColor: Colors.transparent,
        key: Key('localPeerTile_${peer.host}_${peer.port}'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(
            '/peers/0/books',
            extra: {
              'id': 0,
              'name': displayName,
              'url': 'http://${peer.host}:${peer.port}',
              'hasRelayCredentials': false,
              'nodeId': peer.libraryId,
            },
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.menu_book, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showSubtitle)
                        Text(
                          peer.deviceName!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          TranslationService.translate(
                            context, 'status_active',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Consumer<ApiService>(
                  builder: (context, api, _) => IconButton(
                    icon: const Icon(Icons.person_add),
                    tooltip: TranslationService.translate(
                      context, 'connect',
                    ),
                    onPressed: () async {
                      try {
                        await api.connectPeer(
                          displayName,
                          'http://${peer.host}:${peer.port}',
                          libraryUuid: peer.libraryId,
                          ed25519PublicKey: peer.ed25519PublicKey,
                          x25519PublicKey: peer.x25519PublicKey,
                        );
                        if (context.mounted) {
                          context
                              .read<FlashMessageProvider>()
                              .addEphemeralPeer(
                            EphemeralPeerFlash(
                              peerId: 'http://${peer.host}:${peer.port}'
                                      .hashCode &
                                  0x7FFFFFFF,
                              peerName: displayName,
                              peerUrl:
                                  'http://${peer.host}:${peer.port}',
                              nodeId: peer.libraryId,
                              connectedAt: DateTime.now(),
                            ),
                          );
                          _loadAll();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                TranslationService.translate(
                                  context, 'connection_error',
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    switch (_filter) {
      case LibraryFilter.nearby:
        return _buildEmptyStateContent(
          context,
          key: 'networkEmptyNearby',
          icon: Icons.wifi_off,
          iconColor: Colors.grey,
          titleKey: 'no_nearby_peers',
          hintKey: 'no_nearby_peers_hint',
        );
      case LibraryFilter.following:
        final hubOn = context.read<HubDirectoryProvider>().isHubEnabled;
        return _buildEmptyStateContent(
          context,
          key: 'networkEmptyFollowing',
          icon: Icons.bookmark_border,
          iconColor: Colors.deepPurple,
          titleKey: 'no_following_yet',
          hintKey: 'no_following_hint',
          actionWidget: hubOn
              ? ElevatedButton.icon(
                  onPressed: () {
                    final networkScreenState =
                        context.findAncestorStateOfType<_NetworkScreenState>();
                    networkScreenState?._mainTabController?.animateTo(1);
                  },
                  icon: const Icon(Icons.explore),
                  label: Text(
                    TranslationService.translate(context, 'browse_directory_btn'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                )
              : null,
        );
      case LibraryFilter.borrowers:
        return _buildEmptyStateContent(
          context,
          key: 'networkEmptyBorrowers',
          icon: Icons.person_outline,
          iconColor: Colors.orange,
          titleKey: 'no_borrowers_yet',
          hintKey: 'no_borrowers_hint',
          actionWidget: ElevatedButton.icon(
            onPressed: () {
              final networkScreenState =
                  context.findAncestorStateOfType<_NetworkScreenState>();
              networkScreenState?._showAddConnectionSheet(context);
            },
            icon: const Icon(Icons.person_add),
            label: Text(
              TranslationService.translate(context, 'add_first_contact'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      case LibraryFilter.all:
        return _buildEmptyStateContent(
          context,
          key: 'networkEmptyState',
          icon: Icons.people_outline,
          iconColor: Colors.amber,
          titleKey: 'no_contacts_title',
          hintKey: 'no_contacts_hint',
          actionWidget: Column(
            children: [
              ElevatedButton.icon(
                key: const Key('addFirstContactBtn'),
                onPressed: () {
                  final networkScreenState =
                      context.findAncestorStateOfType<_NetworkScreenState>();
                  networkScreenState?._showAddConnectionSheet(context);
                },
                icon: const Icon(Icons.person_add),
                label: Text(
                  TranslationService.translate(context, 'add_first_contact'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('shareInviteEmptyStateBtn'),
                onPressed: () => showInviteShareSheet(context),
                icon: const Icon(Icons.share, size: 20),
                label: Text(
                  TranslationService.translate(
                    context, 'share_invite_empty_state',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildEmptyStateContent(
    BuildContext context, {
    required String key,
    required IconData icon,
    required Color iconColor,
    required String titleKey,
    required String hintKey,
    Widget? actionWidget,
  }) {
    return Center(
      key: Key(key),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, titleKey),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, hintKey),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (actionWidget != null) ...[
              const SizedBox(height: 32),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}

/// Card for connection actions (styled like QuickActionCard).
class _ConnectionActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _ConnectionActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark
                ? color.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// View for Sharing Code (extracted from original state)
class ShareContactView extends StatefulWidget {
  const ShareContactView({super.key});

  @override
  State<ShareContactView> createState() => _ShareContactViewState();
}

class _ShareContactViewState extends State<ShareContactView> {
  String? _qrData;
  String? _inviteLink;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('📱 [QR] ShareContactView.initState()');
    _initQRData();
  }

  Future<void> _initQRData() async {
    debugPrint('📱 [QR] _initQRData() START');
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      debugPrint('📱 [QR] Got ApiService OK');

      // Use the same multi-strategy IP resolution as mDNS/peer handshake
      String? localIp;
      try {
        final info = NetworkInfo();
        final wifiIp = await info.getWifiIP();
        debugPrint('📱 [QR] NetworkInfo.getWifiIP() = $wifiIp');
        if (wifiIp != null && !wifiIp.startsWith('169.254.')) {
          localIp = wifiIp;
        }
      } catch (e) {
        debugPrint('📱 [QR] NetworkInfo error: $e');
      }
      localIp ??= await MdnsService.getValidLanIp();
      debugPrint('📱 [QR] Final localIp = $localIp');

      final configRes = await apiService.getLibraryConfig();
      // Library name from ThemeProvider (single source of truth)
      String libraryName = Provider.of<ThemeProvider>(context, listen: false).libraryName;
      final libraryUuid = configRes.data['library_uuid'] as String?;
      final ed25519Key = configRes.data['ed25519_public_key'] as String?;
      final x25519Key = configRes.data['x25519_public_key'] as String?;
      final relayUrl = configRes.data['relay_url'] as String?;
      final mailboxId = configRes.data['mailbox_id'] as String?;
      final relayWriteToken = configRes.data['relay_write_token'] as String?;
      debugPrint('📱 [QR] libraryName=$libraryName, hasKeys=${ed25519Key != null}, hasRelay=${relayUrl != null}');

      // Build the connection URL: prefer LAN IP, fall back to relay URL
      final String connectUrl;
      if (localIp != null) {
        connectUrl = "http://$localIp:${ApiService.httpPort}";
      } else if (relayUrl != null && mailboxId != null) {
        // No WiFi (e.g. 5G) — use relay URL so the QR code still works
        connectUrl = "relay://$mailboxId";
        debugPrint('📱 [QR] No LAN IP, using relay URL for QR code');
      } else {
        debugPrint('⚠️ QR: No valid LAN IP and no relay configured');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = buildInvitePayload(
        name: libraryName,
        url: connectUrl,
        libraryUuid: libraryUuid,
        ed25519PublicKey: ed25519Key,
        x25519PublicKey: x25519Key,
        relayUrl: relayUrl,
        mailboxId: mailboxId,
        relayWriteToken: relayWriteToken,
      );
      // Precalculate the short invite link (async, falls back to long format)
      final link = await createInviteLink(data, hubBaseUrl: ApiService.hubUrl);
      if (mounted) {
        setState(() {
          _qrData = jsonEncode(data);
          _inviteLink = link;
          _isLoading = false;
        });
        debugPrint('📱 [QR] QR data ready: $_qrData');
      }
    } catch (e, stack) {
      debugPrint('📱 [QR] ERROR in _initQRData: $e');
      debugPrint('📱 [QR] Stack: $stack');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('📱 [QR] build() — isLoading=$_isLoading, qrData=${_qrData != null}');
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_inviteLink != null) ...[
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(context, 'show_code_explanation'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // QR code
          SizedBox(
            width: 200,
            height: 200,
            child: QrImageView(
              key: const Key('myQrCode'),
              data: _inviteLink!,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 16),
          // Numbered steps
          _buildStep(context, 1, TranslationService.translate(context, 'show_code_step_1')),
          const SizedBox(height: 8),
          _buildStep(context, 2, TranslationService.translate(context, 'show_code_step_2')),
          const SizedBox(height: 8),
          _buildStep(context, 3, TranslationService.translate(context, 'show_code_step_3')),
          const SizedBox(height: 16),
          // Copy + Share invite link buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('copyInviteLinkBtn'),
                onPressed: _inviteLink == null ? null : () {
                  Clipboard.setData(ClipboardData(text: _inviteLink!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(
                            context, 'invite_link_copied'),
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.content_copy, size: 18),
                label: Text(
                  TranslationService.translate(context, 'copy_invite_link'),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (btnContext) => OutlinedButton.icon(
                  key: const Key('shareInviteLinkBtn'),
                  onPressed: _inviteLink == null
                      ? null
                      : () async {
                          final box = btnContext.findRenderObject()
                              as RenderBox?;
                          final origin = box != null
                              ? box.localToGlobal(Offset.zero) & box.size
                              : null;
                          try {
                            await Share.share(
                              _inviteLink!,
                              sharePositionOrigin: origin,
                            );
                          } catch (e) {
                            debugPrint(
                              'NetworkScreen: share invite failed: $e',
                            );
                          }
                        },
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'share_invite_link'),
                  ),
                ),
              ),
            ],
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  TranslationService.translate(context, 'qr_error'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(context, 'qr_wifi_suggestion'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStep(BuildContext context, int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pending connections banner - compact, branded
// ---------------------------------------------------------------------------

class _PendingBanner extends StatelessWidget {
  final int count;
  final VoidCallback onAction;

  const _PendingBanner({required this.count, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1A05) : const Color(0xFFFFFBEB);
    final border = isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
    final textColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
    final subtleText = isDark ? const Color(0xFFD97706) : const Color(0xFFB45309);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        border: Border.all(color: border),
        boxShadow: AppDesign.subtleShadow,
      ),
      child: Row(
        children: [
          // Left accent bar
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppDesign.warningGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppDesign.radiusMedium),
                bottomLeft: Radius.circular(AppDesign.radiusMedium),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Count badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppDesign.warningGradient,
              shape: BoxShape.circle,
              boxShadow: AppDesign.glowShadow(const Color(0xFFF59E0B)),
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              TranslationService.translate(context, 'pending_connections_banner')
                  .replaceAll('{count}', '$count'),
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: subtleText,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              TranslationService.translate(context, 'review_connections'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invite banner (teal)
// ---------------------------------------------------------------------------

class _InviteBanner extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  const _InviteBanner({required this.onTap, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: TranslationService.translate(context, 'invite_card_title'),
      child: ScaleOnTap(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [primary.withValues(alpha: 0.15), primary.withValues(alpha: 0.08)]
                  : [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.03)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            border: Border.all(
              color: primary.withValues(alpha: isDark ? 0.25 : 0.15),
            ),
          ),
          child: Row(
            children: [
              // Icon with gradient background
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                ),
                child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(context, 'invite_card_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1A2E35),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TranslationService.translate(context, 'invite_card_subtitle'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF5A7A82),
                      ),
                    ),
                  ],
                ),
              ),
              // CTA arrow
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: primary,
                ),
              ),
              // Dismiss button
              if (onDismiss != null) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 14,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.3),
                    ),
                    tooltip: TranslationService.translate(context, 'close'),
                    onPressed: onDismiss,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hub incoming follow requests section
// ---------------------------------------------------------------------------

/// Expandable section showing incoming hub follow requests with approve/reject/block.
class _HubRequestsSection extends StatefulWidget {
  final List<HubFollow> requests;
  final HubDirectoryProvider provider;

  const _HubRequestsSection({
    required this.requests,
    required this.provider,
  });

  @override
  State<_HubRequestsSection> createState() => _HubRequestsSectionState();
}

class _HubRequestsSectionState extends State<_HubRequestsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final count = widget.requests.length;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Semantics(
            header: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.3),
              child: Row(
                children: [
                  Icon(
                    Icons.how_to_reg,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${TranslationService.translate(context, 'network_hub_requests_title')} ($count)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          ...widget.requests.map(
            (follow) => _IncomingRequestTile(
              follow: follow,
              provider: widget.provider,
            ),
          ),
      ],
    );
  }
}

/// Single incoming follow request tile with approve/reject/block buttons.
class _IncomingRequestTile extends StatelessWidget {
  final HubFollow follow;
  final HubDirectoryProvider provider;

  const _IncomingRequestTile({
    required this.follow,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedName = follow.followerDisplayName ??
        provider.displayNameFor(follow.followerNodeId);
    final hasName = resolvedName != null && resolvedName.isNotEmpty;
    final label = hasName ? resolvedName : follow.followerNodeId;

    return Semantics(
      button: true,
      label: label,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  label.isNotEmpty ? label[0].toUpperCase() : '?',
                  style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: hasName
                      ? const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)
                      : const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: TranslationService.translate(
                  context, 'directory_approve',
                ),
                icon: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                ),
                onPressed: () async {
                  // Seal contact info for the follower if available
                  String? blob;
                  final key = follow.followerX25519PublicKey;
                  if (key != null && key.isNotEmpty) {
                    blob = await provider.sealContactFor(key);
                  }
                  await provider.resolveFollow(
                    follow.id, 'approve', encryptedContact: blob);
                },
              ),
              IconButton(
                tooltip: TranslationService.translate(
                  context, 'directory_reject',
                ),
                icon: const Icon(
                  Icons.cancel_outlined,
                  color: Colors.red,
                ),
                onPressed: () =>
                    provider.resolveFollow(follow.id, 'reject'),
              ),
              IconButton(
                tooltip: TranslationService.translate(
                  context, 'directory_block',
                ),
                icon: const Icon(Icons.block, color: Colors.orange),
                onPressed: () =>
                    provider.resolveFollow(follow.id, 'block'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover tab - hub directory
// ---------------------------------------------------------------------------

/// Public directory tab with search and infinite scroll.
class _DiscoverView extends StatefulWidget {
  const _DiscoverView();

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final provider = context.read<HubDirectoryProvider>();
      provider.loadDirectory(search: query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, provider, _) {
        // ADR-015: GET /api/directory is a public endpoint, so the list is
        // always rendered — whether or not the user has opted in. Users who
        // haven't published their own library see a CTA banner at the top
        // of the list so they can appear in the directory with one tap.

        // Trigger initial load. `hasMore` guards against an infinite
        // rebuild loop when the hub returns an empty directory: after the
        // first fetch completes with 0 profiles, hasMore flips to false,
        // so we stop re-triggering. Pull-to-refresh resets hasMore=true.
        if (provider.profiles.isEmpty &&
            !provider.listLoading &&
            provider.searchQuery == null &&
            provider.hasMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.loadDirectory();
          });
        }

        return Column(
          children: [
            // CTA banner: user is not yet publicly listed. Hidden once the
            // library has been published (isListed == true), regardless of
            // _hubEnabled, so re-enabling hub from Settings doesn't suddenly
            // resurface the banner for an already-listed user.
            if (!provider.isListed)
              _PublishToDirectoryBanner(provider: provider),
            // First-time onboarding banner (one-way relationship explainer)
            if (!provider.isDirectoryOnboardingSeen)
              _DirectoryOnboardingBanner(provider: provider),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: TranslationService.translate(
                      context, 'directory_search_hint'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: TranslationService.translate(
                              context, 'action_clear'),
                          onPressed: () {
                            _searchController.clear();
                            provider.loadDirectory();
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            // Results
            Expanded(child: _buildResults(provider)),
          ],
        );
      },
    );
  }

  Widget _buildResults(HubDirectoryProvider provider) {
    if (provider.listLoading && provider.profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.listError != null && provider.profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(provider.listError!),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => provider.loadDirectory(
                  search: _searchController.text),
              child: Text(
                TranslationService.translate(context, 'action_retry'),
              ),
            ),
          ],
        ),
      );
    }

    if (provider.profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.searchQuery != null
                  ? Icons.search_off
                  : Icons.public_off,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              provider.searchQuery != null
                  ? TranslationService.translate(
                      context, 'directory_no_results')
                  : TranslationService.translate(
                      context, 'directory_empty'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          provider.loadDirectory(search: _searchController.text),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
            provider.loadMoreDirectory();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount:
              provider.profiles.length + (provider.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == provider.profiles.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final profile = provider.profiles[index];
            return _DiscoverCard(profile: profile);
          },
        ),
      ),
    );
  }
}

/// Card for a hub library profile in the Discover tab.
class _DiscoverCard extends StatelessWidget {
  final HubProfile profile;

  const _DiscoverCard({required this.profile});

  bool _isOwnLibrary(HubDirectoryProvider provider) =>
      provider.config?.nodeId == profile.nodeId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HubDirectoryProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = profile.displayName;
    final bookCount = profile.bookCount;
    final isOwn = _isOwnLibrary(provider);
    // True when this library has sent us a pending follow request. Surfaced
    // as a small chip inside the card so the user can spot from Discover
    // that the badge-count on My Network maps to this specific library.
    final hasIncomingRequest = !isOwn &&
        provider.hasIncomingFollowRequestFrom(profile.nodeId);

    return Semantics(
      button: true,
      label: '$name, $bookCount ${TranslationService.translate(context, 'directory_books')}'
          '${isOwn ? ', ${TranslationService.translate(context, 'directory_your_library')}' : ''}'
          '${hasIncomingRequest ? ', ${TranslationService.translate(context, 'directory_wants_to_follow_you')}' : ''}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
              : cs.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          border: Border.all(
            color: isOwn
                ? cs.tertiary.withValues(alpha: 0.3)
                : cs.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          onTap: () => context.push(
            '/directory/${Uri.encodeComponent(profile.nodeId)}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: avatar + name + badge + action
                Row(
                  children: [
                    // Gradient avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: isOwn
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.tertiary,
                                  cs.tertiary.withValues(alpha: 0.7),
                                ],
                              )
                            : AppDesign.refinedSuccessGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isOwn) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.tertiary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    TranslationService.translate(
                                        context, 'directory_your_library'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: cs.tertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          // Meta row: book count + location
                          Row(
                            children: [
                              Icon(Icons.auto_stories,
                                  size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                '$bookCount',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (profile.locationCountry != null &&
                                  profile.locationCountry!.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.location_on_outlined,
                                    size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: 2),
                                Text(
                                  profile.locationCountry!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (profile.requiresApproval) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.verified_user_outlined,
                                    size: 14, color: cs.onSurfaceVariant),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Follow action or chevron
                    if (!isOwn) ...[
                      const SizedBox(width: 8),
                      _buildFollowAction(context, provider, cs, isDark),
                    ] else ...[
                      Icon(Icons.chevron_right,
                          size: 20, color: cs.onSurfaceVariant),
                    ],
                  ],
                ),
                // Incoming follow request marker: this library is waiting for
                // our approval. Placed above the description so the user sees
                // the request context before any library-provided blurb.
                if (hasIncomingRequest) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add_alt_1,
                          size: 13,
                          color: cs.onSecondaryContainer,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            TranslationService.translate(
                                context, 'directory_wants_to_follow_you'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Description
                if (profile.description != null &&
                    profile.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowAction(
    BuildContext context,
    HubDirectoryProvider provider,
    ColorScheme cs,
    bool isDark,
  ) {
    final status = provider.followStatusFor(profile.nodeId);

    if (provider.isBusy(profile.nodeId)) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // Already following: outlined chip style
    if (status == 'active') {
      return _FollowChip(
        label: TranslationService.translate(context, 'directory_following'),
        filled: true,
        color: cs.primary,
        isDark: isDark,
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                TranslationService.translate(ctx, 'directory_unfollow_title'),
              ),
              content: Text(
                TranslationService.translate(
                  ctx, 'directory_unfollow_confirm',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    TranslationService.translate(ctx, 'cancel'),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    TranslationService.translate(
                      ctx, 'directory_unfollow',
                    ),
                  ),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await provider.unfollow(profile.nodeId);
          }
        },
      );
    }

    // Pending: muted chip
    if (status == 'pending') {
      return _FollowChip(
        label: TranslationService.translate(context, 'directory_pending'),
        filled: false,
        color: cs.onSurfaceVariant,
        isDark: isDark,
      );
    }

    // Not following: prominent action chip
    final label = profile.requiresApproval
        ? TranslationService.translate(context, 'directory_request')
        : TranslationService.translate(context, 'directory_follow');
    return _FollowChip(
      label: label,
      filled: true,
      color: const Color(0xFF3A7186),
      isDark: isDark,
      onPressed: () async {
        final ok = await provider.follow(profile.nodeId);
        if (!context.mounted) return;
        if (!ok || provider.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(
                  context, 'directory_follow_error',
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        // Success: confirm to the user. Without this, a follow that
        // requires approval silently switches the chip to "awaiting" —
        // some users perceive it as a missed tap and retry.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                profile.requiresApproval
                    ? 'directory_follow_request_sent'
                    : 'directory_follow_success',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}

/// Styled chip button for follow actions in the directory.
class _FollowChip extends StatelessWidget {
  final String label;
  final bool filled;
  final Color color;
  final bool isDark;
  final VoidCallback? onPressed;

  const _FollowChip({
    required this.label,
    required this.filled,
    required this.color,
    required this.isDark,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: filled
                ? color.withValues(alpha: isDark ? 0.25 : 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: filled ? 0.4 : 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled
                  ? (isDark ? color.withValues(alpha: 0.9) : color)
                  : color.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library relation card - shows peer + follow status with actions
// ---------------------------------------------------------------------------

class _LibraryRelationCard extends StatelessWidget {
  final LibraryRelation relation;
  final VoidCallback onRefresh;
  final ValueChanged<String> onRemoved;
  /// null = still checking, true = online, false = unreachable
  final bool? isOnline;

  const _LibraryRelationCard({
    required this.relation,
    required this.onRefresh,
    required this.onRemoved,
    this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    // Avatar color encodes the dominant connection type
    final Color avatarColor;
    final String avatarTooltipKey;
    if (relation.isPeer && relation.isFollowing) {
      avatarColor = Colors.teal;
      avatarTooltipKey = 'peer_type_both';
    } else if (relation.isPeer) {
      avatarColor = Colors.blue;
      avatarTooltipKey = 'peer_type_direct';
    } else {
      avatarColor = Colors.deepPurple;
      avatarTooltipKey = 'peer_type_following';
    }

    // Status dot color
    final Color? statusColor;
    if (isOnline == true) {
      statusColor = Colors.green;
    } else if (isOnline == false &&
        (relation.peer?.hasRelayCredentials == true || relation.isFollowing)) {
      statusColor = Colors.blueGrey;
    } else if (isOnline == false) {
      statusColor = Colors.grey;
    } else {
      statusColor = null; // still checking
    }

    return Semantics(
      button: true,
      label: relation.name,
      child: Card(
        key: Key('libraryCard_${relation.nodeId}'),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onCardTap(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // Avatar with status dot
                Tooltip(
                  message: TranslationService.translate(
                      context, avatarTooltipKey),
                  child: Stack(
                  children: [
                    _peerAvatar(context, relation, avatarColor),
                    if (statusColor != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).cardColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      )
                    else if (isOnline == null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                  ],
                ),
                ),
                const SizedBox(width: 10),
                // Name + caption
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        relation.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (relation.hasCaption)
                        Text(
                          relation.caption!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // Connection type badge: only when hub-follow only
                      // (P2P-only and dual are self-explanatory from context)
                      if (relation.isFollowing && !relation.isPeer)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _ConnectionTypeBadge(
                            labelKey: 'connection_type_hub',
                            color: Colors.deepPurple,
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions menu
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: TranslationService.translate(context, 'peer_actions'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: _actionConstraints,
                  onPressed: () => _showActionsSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _actionConstraints = BoxConstraints(minWidth: 44, minHeight: 44);

  /// Primary tap: navigate to peer library. Fallback to detail screen if no
  /// library is browsable (no URL and not an active follow).
  void _onCardTap(BuildContext context) {
    if (relation.isPeer && relation.peer?.url != null) {
      final peer = relation.peer!;
      context.push(
        '/peers/${peer.id}/books',
        extra: {
          'id': peer.id,
          'name': relation.name,
          'url': peer.url,
          'hasRelayCredentials': peer.hasRelayCredentials,
          'nodeId': relation.nodeId,
          'caption': relation.caption,
        },
      );
    } else if (relation.isFollowing && relation.follow!.isActive) {
      context.push('/directory/${Uri.encodeComponent(relation.nodeId)}');
    } else {
      // No browsable library -- fall back to profile
      context.push(
        '/peers/${relation.peer?.id ?? 0}/details',
        extra: relation,
      );
    }
  }

  /// Bottom sheet with contextual actions for this peer.
  void _showActionsSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Text(
                  relation.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),

                // View profile
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(TranslationService.translate(
                      context, 'view_profile')),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final result = await context.push(
                      '/peers/${relation.peer?.id ?? 0}/details',
                      extra: relation,
                    );
                    if (result == 'deleted') {
                      onRemoved(relation.nodeId);
                    }
                  },
                ),

                // Sync (P2P peers only)
                if (relation.isPeer && relation.peer?.url != null)
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: Text(TranslationService.translate(
                        context, 'tooltip_sync')),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        final api = context.read<ApiService>();
                        await api.syncPeer(relation.peer!.url!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(TranslationService.translate(
                                context, 'sync_started')),
                          ));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(TranslationService.translate(
                                context, 'sync_failed')),
                            backgroundColor: Colors.orange,
                          ));
                        }
                      }
                    },
                  ),

                // Unfollow (active follows only)
                if (relation.isFollowing && !relation.followPending)
                  ListTile(
                    leading: Icon(Icons.bookmark_remove, color: cs.error),
                    title: Text(
                      TranslationService.translate(context, 'lib_unfollow'),
                      style: TextStyle(color: cs.error),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onRemoved(relation.nodeId);
                      context.read<HubDirectoryProvider>()
                          .unfollow(relation.nodeId);
                    },
                  ),

                // Disconnect peer
                if (relation.isPeer)
                  ListTile(
                    leading: Icon(Icons.link_off, color: cs.error),
                    title: Text(
                      TranslationService.translate(
                          context, 'delete_contact_title'),
                      style: TextStyle(color: cs.error),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(TranslationService.translate(
                              ctx, 'delete_contact_title')),
                          content: Text(
                            '${TranslationService.translate(ctx, 'confirm_delete')} '
                            '${relation.name}?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(TranslationService.translate(
                                  ctx, 'cancel')),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(TranslationService.translate(
                                  ctx, 'delete_contact_btn')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        onRemoved(relation.nodeId);
                        context.read<ApiService>()
                            .deletePeer(relation.peer!.id);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build the peer avatar: custom DiceBear if available, DiceBear initials fallback.
  /// Uses Selector to rebuild only when the hub avatar for this specific node changes.
  Widget _peerAvatar(BuildContext context, LibraryRelation relation, Color fallbackColor) {
    // If the relation already has an avatar (from P2P sync), use it directly — no need for Selector.
    if (relation.avatarConfig != null) {
      return _buildAvatarWidget(relation.avatarConfig!, relation, fallbackColor);
    }
    // Otherwise, reactively wait for the hub avatar cache to be populated.
    return Selector<HubDirectoryProvider, bool>(
      selector: (_, p) => p.avatarConfigFor(relation.nodeId) != null,
      builder: (context, _, __) {
        final config = Provider.of<HubDirectoryProvider>(context, listen: false)
            .avatarConfigFor(relation.nodeId);
        return _buildAvatarWidget(config, relation, fallbackColor);
      },
    );
  }

  Widget _buildAvatarWidget(AvatarConfig? config, LibraryRelation relation, Color fallbackColor) {
    final String url;
    if (config != null && !config.isAsset) {
      url = config.toUrl(size: 72);
    } else {
      url = AvatarConfig(seed: relation.name, style: 'initials')
          .toUrl(size: 72);
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: fallbackColor.withValues(alpha: 0.15),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          placeholder: (_, _) => _initialLetterFallback(relation, fallbackColor),
          errorWidget: (_, _, _) => _initialLetterFallback(relation, fallbackColor),
        ),
      ),
    );
  }

  /// Synchronous single-letter fallback shown while CachedNetworkImage loads.
  Widget _initialLetterFallback(LibraryRelation relation, Color bgColor) {
    final name = relation.name;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: bgColor,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover tab banners (publish CTA + first-visit onboarding)
// ---------------------------------------------------------------------------

/// CTA banner shown at the top of the Discover tab when the user's library
/// is not yet listed in the public directory (ADR-015).
///
/// Tapping "Publish" triggers `HubDirectoryProvider.enableAndPublish`, which
/// flips `_hubEnabled` + `isListed` + registers + syncs catalog in one pass.
/// No navigation required — the banner disappears on success.
class _PublishToDirectoryBanner extends StatefulWidget {
  final HubDirectoryProvider provider;

  const _PublishToDirectoryBanner({required this.provider});

  @override
  State<_PublishToDirectoryBanner> createState() =>
      _PublishToDirectoryBannerState();
}

class _PublishToDirectoryBannerState extends State<_PublishToDirectoryBanner> {
  bool _busy = false;

  Future<void> _onPublish() async {
    if (_busy) return;
    setState(() => _busy = true);

    final themeProvider = context.read<ThemeProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final libraryName = themeProvider.libraryName;
    final country = themeProvider.country;

    final ok = await widget.provider.enableAndPublish(
      displayName: libraryName,
      locationCountry: country,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      // Keep caching toggles aligned with the Settings flow so a user who
      // goes through the banner ends up with the same capabilities as one
      // who used Settings > Directory.
      if (!themeProvider.peerOfflineCachingEnabled) {
        await themeProvider.setPeerOfflineCachingEnabled(true);
      }
      if (!themeProvider.allowLibraryCaching) {
        await themeProvider.setAllowLibraryCaching(true);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(
              context, 'directory_publish_success',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = widget.provider.configError ??
          TranslationService.translate(context, 'error_network');
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: cs.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: TranslationService.translate(
          context, 'directory_publish_banner_title'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
              cs.tertiary.withValues(alpha: isDark ? 0.18 : 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.public, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(
                          context, 'directory_publish_banner_title'),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(
                  context, 'directory_publish_banner_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  key: const Key('directoryPublishCta'),
                  onPressed: _busy ? null : _onPublish,
                  icon: _busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : const Icon(Icons.public, size: 18),
                  label: Text(
                    TranslationService.translate(
                        context, 'directory_publish_banner_cta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dismissable banner explaining the unidirectional nature of the public
/// directory, shown once when the user opens the Discover tab for the first
/// time. Dismissed via [HubDirectoryProvider.markDirectoryOnboardingSeen].
class _DirectoryOnboardingBanner extends StatelessWidget {
  final HubDirectoryProvider provider;

  const _DirectoryOnboardingBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: TranslationService.translate(context, 'discover_onboard_title'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                color: cs.secondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                        context, 'discover_onboard_title'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TranslationService.translate(
                        context, 'discover_onboard_desc'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSecondaryContainer,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: provider.markDirectoryOnboardingSeen,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.secondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        TranslationService.translate(
                            context, 'discover_onboard_dismiss'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection type badge chip
// ---------------------------------------------------------------------------

/// Small chip showing the connection type label (hub-follow only, P2P, etc.).
/// Used in [_LibraryRelationCard] to help users distinguish connection modes.
class _ConnectionTypeBadge extends StatelessWidget {
  final String labelKey;
  final Color color;

  const _ConnectionTypeBadge({required this.labelKey, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        TranslationService.translate(context, labelKey),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
