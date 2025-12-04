import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class P2PScreen extends StatefulWidget {
  const P2PScreen({super.key});

  @override
  State<P2PScreen> createState() => _P2PScreenState();
}

class _P2PScreenState extends State<P2PScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _localIp;
  String? _libraryName;
  bool _isLoading = true;
  String? _qrData;
  MobileScannerController cameraController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final info = NetworkInfo();

    try {
      // Get Local IP
      try {
        _localIp = await info.getWifiIP();
      } catch (e) {
        // getWifiIP not supported on Web platform
        debugPrint("Error getting IP: $e");
        _localIp = 'localhost';
      }
      _localIp ??= '127.0.0.1'; // Fallback


      // Get Library Config
      try {
        final response = await apiService.getLibraryConfig();
        if (response.statusCode == 200) {
          final data = response.data;
          _libraryName = data['library_name'];
        }
      } catch (e) {
        debugPrint("Error getting config: $e");
      }
      _libraryName ??= TranslationService.translate(context, 'my_library_title'); // Fallback

      if (_localIp != null && _libraryName != null) {
        // Construct QR Data
        // Assuming backend runs on port 8000
        final data = {"name": _libraryName, "url": "http://$_localIp:8000"};
        _qrData = jsonEncode(data);
      }
    } catch (e) {
      // Error initializing P2P
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
            break; // Process first valid code
          }
        } catch (e) {
          // Not a valid JSON or our format
        }
      }
    }
  }

  Future<void> _connect(String name, String url) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.connectPeer(name, url);

      if (mounted) {
        Navigator.pop(context); // Pop loading
        Navigator.pop(context); // Pop P2P screen to return to previous screen
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("${TranslationService.translate(context, 'connected_to')} $name!")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("${TranslationService.translate(context, 'connection_failed')}: $e")));
      }
    }
  }

  void _showManualConnectionDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController(text: 'http://localhost:8001');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'manual_connection_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: TranslationService.translate(context, 'library_name')),
            ),
            TextField(
              controller: urlController,
              decoration: InputDecoration(labelText: TranslationService.translate(context, 'library_url')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                Navigator.pop(context);
                _connect(nameController.text, urlController.text);
              }
            },
            child: Text(TranslationService.translate(context, 'connect')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKid = Provider.of<ThemeProvider>(context).isKid;
    final title = isKid ? TranslationService.translate(context, 'friends_libraries_title') : TranslationService.translate(context, 'p2p_title');

    return Scaffold(
      appBar: GenieAppBar(
        title: title,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: _showManualConnectionDialog,
            tooltip: 'Manual Connection',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).appBarTheme.foregroundColor,
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor: Theme.of(context).appBarTheme.foregroundColor?.withOpacity(0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: TranslationService.translate(context, 'tab_share_code'), icon: const Icon(Icons.qr_code)),
            Tab(text: TranslationService.translate(context, 'tab_scan_code'), icon: const Icon(Icons.camera_alt)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildShareTab(), _buildScanTab()],
      ),
    );
  }

  Widget _buildShareTab() {
    if (_isLoading) {
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
            ElevatedButton(onPressed: _initData, child: Text(TranslationService.translate(context, 'retry'))),
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
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      _tabController.animateTo(1);
                    },
                    child: Text(
                      TranslationService.translate(context, 'scan_qr_code'),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 16,
                        letterSpacing: 1.0,
                        decoration: TextDecoration.underline,
                      ),
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
        // Overlay
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
        // Controls
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

// Helper class for overlay shape (simplified version of what libraries usually provide)
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

    final boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderOffset * 2,
      _cutOutSize - borderOffset * 2,
    );

    canvas
      ..saveLayer(
        rect,
        backgroundPaint,
      )
      ..drawRect(
        rect,
        backgroundPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          cutOutRect,
          Radius.circular(_borderRadius),
        ),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();

    final path = Path();

    path.moveTo(cutOutRect.left, cutOutRect.top + _borderLength);
    path.lineTo(cutOutRect.left, cutOutRect.top + _borderRadius);
    path.quadraticBezierTo(
      cutOutRect.left,
      cutOutRect.top,
      cutOutRect.left + _borderRadius,
      cutOutRect.top,
    );
    path.lineTo(cutOutRect.left + _borderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.top + _borderLength);
    path.lineTo(cutOutRect.right, cutOutRect.top + _borderRadius);
    path.quadraticBezierTo(
      cutOutRect.right,
      cutOutRect.top,
      cutOutRect.right - _borderRadius,
      cutOutRect.top,
    );
    path.lineTo(cutOutRect.right - _borderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right, cutOutRect.bottom - _borderLength);
    path.lineTo(cutOutRect.right, cutOutRect.bottom - _borderRadius);
    path.quadraticBezierTo(
      cutOutRect.right,
      cutOutRect.bottom,
      cutOutRect.right - _borderRadius,
      cutOutRect.bottom,
    );
    path.lineTo(cutOutRect.right - _borderLength, cutOutRect.bottom);

    path.moveTo(cutOutRect.left, cutOutRect.bottom - _borderLength);
    path.lineTo(cutOutRect.left, cutOutRect.bottom - _borderRadius);
    path.quadraticBezierTo(
      cutOutRect.left,
      cutOutRect.bottom,
      cutOutRect.left + _borderRadius,
      cutOutRect.bottom,
    );
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
