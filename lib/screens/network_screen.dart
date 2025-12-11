import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import '../models/contact.dart';
import '../models/network_member.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
// ThemeProvider import removed - not used in this screen
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Filter options for the network list
enum NetworkFilter { all, libraries, contacts }

/// Unified screen displaying both Contacts and Network Libraries (Peers)
/// Replaces the separate ContactsScreen and PeerListScreen
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Unified list state
  List<NetworkMember> _members = [];
  bool _isLoading = true;
  NetworkFilter _filter = NetworkFilter.all;
  Timer? _refreshTimer;

  // QR State
  String? _localIp;
  String? _libraryName;
  bool _isLoadingQR = true;
  String? _qrData;
  MobileScannerController cameraController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllMembers();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _tabController.index == 0) _loadAllMembers(silent: true);
    });
    _initQRData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    cameraController.dispose();
    super.dispose();
  }

  /// Load both contacts and peers, merge into unified list
  Future<void> _loadAllMembers({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      // Fetch config to exclude own library from peers
      String? myUrl;
      try {
        final configRes = await api.getLibraryConfig();
        myUrl = configRes.data['default_uri'] as String?;
      } catch (e) {
        debugPrint('Could not get library config: $e');
      }

      // Fetch contacts and peers in parallel
      final results = await Future.wait([
        api.getContacts(libraryId: 1), // TODO: Get from auth context
        api.getPeers(),
      ]);

      final contactsRes = results[0];
      final peersRes = results[1];

      // Parse contacts
      final List<dynamic> contactsJson = contactsRes.data['contacts'] ?? [];
      final contacts = contactsJson
          .map((json) => Contact.fromJson(json))
          .map((c) => NetworkMember.fromContact(c))
          .toList();

      // Parse peers (exclude own library)
      final List<dynamic> peersJson = (peersRes.data['data'] ?? []) as List;
      final peers = peersJson
          .where((peer) => myUrl == null || peer['url'] != myUrl)
          .map((p) => NetworkMember.fromPeer(p))
          .toList();

      // Merge and sort: network libraries first, then local contacts
      final allMembers = [...peers, ...contacts];
      allMembers.sort((a, b) {
        // Network first
        if (a.source != b.source) {
          return a.source == NetworkMemberSource.network ? -1 : 1;
        }
        // Then alphabetically
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _members = allMembers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading network members: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Get filtered list based on current filter
  List<NetworkMember> get _filteredMembers {
    switch (_filter) {
      case NetworkFilter.all:
        return _members;
      case NetworkFilter.libraries:
        return _members
            .where((m) =>
                m.source == NetworkMemberSource.network ||
                m.type == NetworkMemberType.library)
            .toList();
      case NetworkFilter.contacts:
        return _members
            .where((m) => m.source == NetworkMemberSource.local)
            .toList();
    }
  }

  // --- Actions ---

  Future<void> _deleteMember(NetworkMember member) async {
    final api = Provider.of<ApiService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(member.source == NetworkMemberSource.network
            ? TranslationService.translate(context, 'dialog_remove_library_title')
            : TranslationService.translate(context, 'delete_contact_title')),
        content: Text(
            '${TranslationService.translate(context, 'confirm_delete')} ${member.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'delete_contact_btn')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (member.source == NetworkMemberSource.network) {
          await api.deletePeer(member.id);
        } else {
          await api.deleteContact(member.id);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    TranslationService.translate(context, 'contact_deleted'))),
          );
          _loadAllMembers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _syncPeer(NetworkMember member) async {
    if (member.source != NetworkMemberSource.network || member.url == null) {
      return;
    }
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.syncPeer(member.url!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  TranslationService.translate(context, 'sync_started'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    }
  }

  // --- QR Logic ---

  Future<void> _initQRData() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final info = NetworkInfo();

    try {
      try {
        _localIp = await info.getWifiIP();
      } catch (e) {
        _localIp = 'localhost';
      }
      _localIp ??= '127.0.0.1';

      try {
        final response = await apiService.getLibraryConfig();
        if (response.statusCode == 200) {
          _libraryName = response.data['library_name'];
        }
      } catch (e) {
        debugPrint("Error getting config: $e");
      }
      if (!mounted) return;
      _libraryName ??=
          TranslationService.translate(context, 'my_library_title');

      if (_localIp != null && _libraryName != null) {
        final data = {"name": _libraryName, "url": "http://$_localIp:8000"};
        _qrData = jsonEncode(data);
      }
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) setState(() => _isLoadingQR = false);
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        try {
          final data = jsonDecode(barcode.rawValue!);
          if (data['name'] != null && data['url'] != null) {
            _connect(data['name'], data['url']);
            break;
          }
        } catch (e) {
          // invalid json
        }
      }
    }
  }

  Future<void> _connect(String name, String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.connectPeer(name, url);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "${TranslationService.translate(context, 'connected_to')} $name!"),
          duration: const Duration(seconds: 2),
        ));
        _tabController.animateTo(0);
        _loadAllMembers();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "${TranslationService.translate(context, 'connection_failed')}: $e")));
      }
    }
  }

  void _showManualConnectionDialog() {
    final nameController = TextEditingController();
    final urlController =
        TextEditingController(text: 'http://localhost:8001');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          bool isLoading = false;

          Future<void> handleConnect() async {
            if (nameController.text.isEmpty || urlController.text.isEmpty) {
              return;
            }

            setState(() => isLoading = true);

            // Capture context-dependent objects before async gap
            final messenger = ScaffoldMessenger.of(dialogContext);
            final navigator = Navigator.of(dialogContext);
            final connectedToText = TranslationService.translate(dialogContext, 'connected_to');
            final connectionFailedText = TranslationService.translate(dialogContext, 'connection_failed');
            final apiService = Provider.of<ApiService>(context, listen: false);
            final libraryName = nameController.text;

            try {
              await apiService.connectPeer(libraryName, urlController.text);

              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(SnackBar(
                content: Text('$connectedToText $libraryName!'),
                duration: const Duration(seconds: 2),
              ));
              _loadAllMembers();
            } catch (e) {
              setState(() => isLoading = false);
              if (!mounted) return;
              messenger.showSnackBar(SnackBar(
                content: Text('$connectionFailedText: $e'),
                duration: const Duration(seconds: 3),
              ));
            }
          }

          return AlertDialog(
            title: Text(TranslationService.translate(
                context, 'manual_connection_title')),
            content: isLoading
                ? const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                            labelText: TranslationService.translate(
                                context, 'library_name')),
                        enabled: !isLoading,
                      ),
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                            labelText: TranslationService.translate(
                                context, 'library_url')),
                        enabled: !isLoading,
                      ),
                    ],
                  ),
            actions: isLoading
                ? []
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child:
                          Text(TranslationService.translate(context, 'cancel')),
                    ),
                    TextButton(
                      onPressed: handleConnect,
                      child: Text(
                          TranslationService.translate(context, 'connect')),
                    ),
                  ],
          );
        },
      ),
    );
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'nav_network'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip:
                TranslationService.translate(context, 'network_search_title'),
            onPressed: () => context.push('/network-search'),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Manual Connection',
            onPressed: _showManualConnectionDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor:
              Theme.of(context).buttonTheme.colorScheme?.onPrimary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
                icon: const Icon(Icons.list),
                text: TranslationService.translate(context, 'tab_list')),
            Tab(
                icon: const Icon(Icons.qr_code_scanner),
                text: TranslationService.translate(context, 'tab_scan_code')),
            Tab(
                icon: const Icon(Icons.qr_code),
                text: TranslationService.translate(context, 'tab_share_code')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMemberList(),
          _buildScanTab(),
          _buildShareTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () async {
                await context.push('/contacts/add');
                _loadAllMembers();
              },
              tooltip: TranslationService.translate(context, 'add_contact'),
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: Text(TranslationService.translate(context, 'filter_all_contacts')),
            selected: _filter == NetworkFilter.all,
            onSelected: (selected) {
              if (selected) setState(() => _filter = NetworkFilter.all);
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(TranslationService.translate(context, 'filter_libraries')),
            selected: _filter == NetworkFilter.libraries,
            onSelected: (selected) {
              if (selected) setState(() => _filter = NetworkFilter.libraries);
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(TranslationService.translate(context, 'filter_contacts_only')),
            selected: _filter == NetworkFilter.contacts,
            onSelected: (selected) {
              if (selected) setState(() => _filter = NetworkFilter.contacts);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMemberList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredMembers;

    // Always show filter chips, even when empty
    return Column(
      children: [
        _buildFilterChips(),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 80,
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      TranslationService.translate(context, 'no_network_members'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      TranslationService.translate(
                          context, 'add_contact_or_scan_help'),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 16, height: 1.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAllMembers,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _buildMemberCard(filtered[index]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMemberCard(NetworkMember member) {
    final isNetwork = member.source == NetworkMemberSource.network;
    final isPending = member.isPending;

    // Determine icon and color
    IconData icon;
    Color iconColor;
    Color bgColor;

    if (isNetwork) {
      icon = isPending ? Icons.hourglass_empty : Icons.public;
      iconColor = isPending ? Colors.orange : Colors.indigo;
      bgColor = isPending
          ? Colors.orange.withValues(alpha: 0.1)
          : Colors.indigo.withValues(alpha: 0.1);
    } else if (member.type == NetworkMemberType.borrower) {
      icon = Icons.person;
      iconColor = Colors.blue;
      bgColor = Colors.blue.withValues(alpha: 0.1);
    } else {
      icon = Icons.library_books;
      iconColor = Colors.purple;
      bgColor = Colors.purple.withValues(alpha: 0.1);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: bgColor,
          child: Icon(icon, color: iconColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isPending ? Colors.grey[700] : null,
                ),
              ),
            ),
            if (isNetwork)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPending
                        ? Colors.orange.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPending ? Icons.hourglass_empty : Icons.cloud_done,
                      size: 12,
                      color: isPending ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      member.displayStatus,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPending ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            if (!isNetwork && member.isActive == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Actif',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            member.secondaryInfo,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ),
        trailing: _buildMemberActions(member),
        onTap: () => _onMemberTap(member),
      ),
    );
  }

  Widget _buildMemberActions(NetworkMember member) {
    if (member.source == NetworkMemberSource.network) {
      if (member.isPending) {
        return IconButton(
          icon: const Icon(Icons.cancel_outlined, color: Colors.orange),
          tooltip: TranslationService.translate(context, 'tooltip_cancel_request'),
          onPressed: () => _deleteMember(member),
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.indigo),
              tooltip: TranslationService.translate(context, 'tooltip_sync'),
              onPressed: () => _syncPeer(member),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: TranslationService.translate(context, 'tooltip_remove_library'),
              onPressed: () => _deleteMember(member),
            ),
          ],
        );
      }
    } else {
      // Local contact
      return IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        tooltip: TranslationService.translate(context, 'delete_contact_btn'),
        onPressed: () => _deleteMember(member),
      );
    }
  }

  void _onMemberTap(NetworkMember member) {
    if (member.source == NetworkMemberSource.network) {
      if (member.isPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(TranslationService.translate(
                  context, 'library_not_accepted'))),
        );
      } else {
        // Navigate to peer's book list
        context.push('/peers/${member.id}/books', extra: {
          'id': member.id,
          'name': member.name,
          'url': member.url,
        });
      }
    } else {
      // Navigate to contact details
      context.push('/contacts/${member.id}');
    }
  }

  Widget _buildShareTab() {
    if (_isLoadingQR) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_qrData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text(TranslationService.translate(context, 'qr_error'),
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text("IP: ${_localIp ?? 'Unknown'}",
                style: const TextStyle(color: Colors.grey)),
            Text("Name: ${_libraryName ?? 'Unknown'}",
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: _initQRData,
                child: Text(TranslationService.translate(context, 'retry'))),
          ],
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: _qrData!,
                    version: QrVersions.auto,
                    size: 240.0,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _libraryName!,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (_qrData != null)
                    Text(
                      (jsonDecode(_qrData!)['url'] as String)
                          .replaceAll('http://', ''),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontFamily: 'Courier',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              TranslationService.translate(context, 'share_code_instruction'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanTab() {
    return Stack(
      children: [
        MobileScanner(
          controller: cameraController,
          onDetect: _onDetect,
        ),
        Container(
          decoration: ShapeDecoration(
            shape: QrScannerOverlayShape(
              borderColor: Theme.of(context).primaryColor,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 10,
              cutOutSize: 300,
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.flash_on, size: 32),
                iconSize: 32.0,
                onPressed: () => cameraController.toggleTorch(),
              ),
              const SizedBox(width: 40),
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.flip_camera_ios, size: 32),
                iconSize: 32.0,
                onPressed: () => cameraController.switchCamera(),
              ),
            ],
          ),
        ),
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                TranslationService.translate(context, 'scan_instruction'),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Helper class for overlay shape
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 10.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final localCutOutSize = cutOutSize;
    final localBorderLength = borderLength;
    final localBorderRadius = borderRadius;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - localCutOutSize / 2 + borderOffset,
      rect.top + height / 2 - localCutOutSize / 2 + borderOffset,
      localCutOutSize - borderOffset * 2,
      localCutOutSize - borderOffset * 2,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      ..drawRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(localBorderRadius)),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();

    final path = Path();
    path.moveTo(cutOutRect.left, cutOutRect.top + localBorderLength);
    path.lineTo(cutOutRect.left, cutOutRect.top + localBorderRadius);
    path.quadraticBezierTo(cutOutRect.left, cutOutRect.top,
        cutOutRect.left + localBorderRadius, cutOutRect.top);
    path.lineTo(cutOutRect.left + localBorderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.top + localBorderLength);
    path.lineTo(cutOutRect.right, cutOutRect.top + localBorderRadius);
    path.quadraticBezierTo(cutOutRect.right, cutOutRect.top,
        cutOutRect.right - localBorderRadius, cutOutRect.top);
    path.lineTo(cutOutRect.right - localBorderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.bottom - localBorderLength);
    path.lineTo(cutOutRect.right, cutOutRect.bottom - localBorderRadius);
    path.quadraticBezierTo(cutOutRect.right, cutOutRect.bottom,
        cutOutRect.right - localBorderRadius, cutOutRect.bottom);
    path.lineTo(cutOutRect.right - localBorderLength, cutOutRect.bottom);

    path.moveTo(cutOutRect.left, cutOutRect.bottom - localBorderLength);
    path.lineTo(cutOutRect.left, cutOutRect.bottom - localBorderRadius);
    path.quadraticBezierTo(cutOutRect.left, cutOutRect.bottom,
        cutOutRect.left + localBorderRadius, cutOutRect.bottom);
    path.lineTo(cutOutRect.left + localBorderLength, cutOutRect.bottom);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
    );
  }
}
