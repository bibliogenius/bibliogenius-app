import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';

class PeerListScreen extends StatefulWidget {
  const PeerListScreen({super.key});

  @override
  State<PeerListScreen> createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Peer List State
  List<dynamic> _peers = [];
  bool _isLoadingPeers = true;
  Timer? _refreshTimer;

  // P2P/QR State
  String? _localIp;
  String? _libraryName;
  bool _isLoadingQR = true;
  String? _qrData;
  MobileScannerController cameraController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Init Peer List
    _fetchPeers();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _tabController.index == 0) _fetchPeers(silent: true);
    });

    // Init QR Data
    _initQRData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    cameraController.dispose();
    super.dispose();
  }

  // --- Peer List Logic ---

  Future<void> _fetchPeers({bool silent = false}) async {
    if (!silent && _peers.isEmpty) setState(() => _isLoadingPeers = true);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final configRes = await api.getLibraryConfig();
      final myUrl = configRes.data['default_uri'] as String?;
      
      final res = await api.getPeers();
      if (mounted) {
        setState(() {
          final allPeers = (res.data['data'] ?? []) as List;
          _peers = allPeers.where((peer) {
            if (myUrl != null && peer['url'] == myUrl) return false;
            return true;
          }).toList();
          _isLoadingPeers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPeers = false);
    }
  }

  Future<void> _addToFriends(Map<String, dynamic> peer) async {
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isPro = themeProvider.isLibrarian;
    
    try {
      await api.createContact({
        'name': peer['name'],
        'type': isPro ? 'library' : 'borrower',
        'email': null,
        'phone': null,
        'notes': '${TranslationService.translate(context, 'added_from_network')} (URL: ${peer['url']})',
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${peer['name']} ${isPro ? TranslationService.translate(context, 'added_to_borrowers') : TranslationService.translate(context, 'added_to_contacts')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_adding')}: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeletePeer(Map<String, dynamic> peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'dialog_remove_library_title')),
        content: Text(TranslationService.translate(context, 'dialog_remove_library_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'btn_remove')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        await api.deletePeer(peer['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(TranslationService.translate(context, 'library_removed'))),
          );
          _fetchPeers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${TranslationService.translate(context, 'error_removing')}: $e')),
          );
        }
      }
    }
  }

  // --- QR / P2P Logic ---

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
      _libraryName ??= TranslationService.translate(context, 'my_library_title');

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
          content: Text("${TranslationService.translate(context, 'connected_to')} $name!"),
          duration: const Duration(seconds: 2),
        ));
        // Switch back to list tab to see result
        _tabController.animateTo(0);
        _fetchPeers();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("${TranslationService.translate(context, 'connection_failed')}: $e")
        ));
      }
    }
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'network_libraries_title'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: TranslationService.translate(context, 'network_search_title'),
            onPressed: () => context.push('/network-search'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).buttonTheme.colorScheme?.onPrimary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(icon: Icon(Icons.list), text: "Libraries"), // TODO: Translate
            Tab(icon: const Icon(Icons.qr_code_scanner), text: TranslationService.translate(context, 'tab_scan_code')),
            Tab(icon: const Icon(Icons.qr_code), text: TranslationService.translate(context, 'tab_share_code')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPeerList(),
          _buildScanTab(),
          _buildShareTab(),
        ],
      ),
    );
  }

  Widget _buildPeerList() {
    return _isLoadingPeers
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _fetchPeers,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _peers.length,
              itemBuilder: (context, index) {
                final peer = _peers[index];
                final isPending = peer['status'] == 'pending';
                
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.1),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: isPending 
                          ? Colors.orange.withOpacity(0.1) 
                          : Colors.indigo.withOpacity(0.1),
                      child: Icon(
                        isPending ? Icons.hourglass_empty : Icons.public,
                        color: isPending ? Colors.orange : Colors.indigo,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            peer['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: isPending ? Colors.grey[700] : Colors.black87,
                            ),
                          ),
                        ),
                        if (isPending)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              TranslationService.translate(context, 'status_waiting'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        isPending 
                          ? '${peer['url']} • ${TranslationService.translate(context, 'request_sent')}' 
                          : peer['url'],
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ),
                    trailing: isPending
                        ? IconButton(
                            icon: const Icon(Icons.cancel_outlined, color: Colors.orange),
                            tooltip: TranslationService.translate(context, 'tooltip_cancel_request'),
                            onPressed: () => _confirmDeletePeer(peer),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.sync, color: Colors.indigo),
                                tooltip: TranslationService.translate(context, 'tooltip_sync'),
                                onPressed: () async {
                                  final api = Provider.of<ApiService>(context, listen: false);
                                  await api.syncPeer(peer['url']);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(TranslationService.translate(context, 'sync_started'))),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.person_add_alt_1, color: Colors.green),
                                tooltip: TranslationService.translate(context, 'tooltip_add_contact'),
                                onPressed: () => _addToFriends(peer),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: TranslationService.translate(context, 'tooltip_remove_library'),
                                onPressed: () => _confirmDeletePeer(peer),
                              ),
                            ],
                          ),
                    onTap: isPending 
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(TranslationService.translate(context, 'library_not_accepted'))),
                          );
                        }
                      : () {
                          context.push('/peers/${peer['id']}/books', extra: peer);
                        },
                  ),
                );
              },
            ),
          );
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
            Text(TranslationService.translate(context, 'qr_error'), style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text("IP: ${_localIp ?? 'Unknown'}", style: const TextStyle(color: Colors.grey)),
            Text("Name: ${_libraryName ?? 'Unknown'}", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _initQRData, child: Text(TranslationService.translate(context, 'retry'))),
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
                    color: Colors.black.withOpacity(0.1),
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
                      (jsonDecode(_qrData!)['url'] as String).replaceAll('http://', ''),
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
    final _cutOutSize = cutOutSize;
    final _borderLength = borderLength;
    final _borderRadius = borderRadius;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderOffset * 2,
      _cutOutSize - borderOffset * 2,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      ..drawRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(_borderRadius)),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();

    final path = Path();
    path.moveTo(cutOutRect.left, cutOutRect.top + _borderLength);
    path.lineTo(cutOutRect.left, cutOutRect.top + _borderRadius);
    path.quadraticBezierTo(cutOutRect.left, cutOutRect.top, cutOutRect.left + _borderRadius, cutOutRect.top);
    path.lineTo(cutOutRect.left + _borderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.top + _borderLength);
    path.lineTo(cutOutRect.right, cutOutRect.top + _borderRadius);
    path.quadraticBezierTo(cutOutRect.right, cutOutRect.top, cutOutRect.right - _borderRadius, cutOutRect.top);
    path.lineTo(cutOutRect.right - _borderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.bottom - _borderLength);
    path.lineTo(cutOutRect.right, cutOutRect.bottom - _borderRadius);
    path.quadraticBezierTo(cutOutRect.right, cutOutRect.bottom, cutOutRect.right - _borderRadius, cutOutRect.bottom);
    path.lineTo(cutOutRect.right - _borderLength, cutOutRect.bottom);

    path.moveTo(cutOutRect.left, cutOutRect.bottom - _borderLength);
    path.lineTo(cutOutRect.left, cutOutRect.bottom - _borderRadius);
    path.quadraticBezierTo(cutOutRect.left, cutOutRect.bottom, cutOutRect.left + _borderRadius, cutOutRect.bottom);
    path.lineTo(cutOutRect.left + _borderLength, cutOutRect.bottom);

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
