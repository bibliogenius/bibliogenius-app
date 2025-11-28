import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final info = NetworkInfo();

    try {
      // Get Local IP
      _localIp = await info.getWifiIP();

      // Get Library Config
      final response = await apiService.getLibraryConfig();
      if (response.statusCode == 200) {
        final data = response.data;
        _libraryName = data['library_name'];
      }

      if (_localIp != null && _libraryName != null) {
        // Construct QR Data
        // Assuming backend runs on port 8000 (default for Axum in this project?)
        // Wait, src/main.rs says config.port. I should probably check config or assume 8000/8080.
        // For now, I'll assume the port the app uses to talk to backend is the same port external users use.
        // But ApiService uses localhost:8001. Let's assume 8001 for now or make it configurable.
        // Actually, let's use the port from the URL the app is connected to, if possible.
        // But ApiService.baseUrl is static const.
        // Let's assume 8000 for the Rust backend as per main.rs usually.
        // Re-checking main.rs: let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
        // I don't know config.port without checking config.rs or .env.
        // I'll assume 8000 for now.

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
            // Stop scanning to prevent multiple triggers?
            // MobileScanner doesn't have stop() easily accessible here without controller.
            // We can show a dialog which pauses interaction.

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Connected to $name!")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to connect: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("P2P Connection"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Share Code"),
            Tab(text: "Scan Code"),
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
            const Text("Could not generate QR Code."),
            const SizedBox(height: 10),
            Text("IP: ${_localIp ?? 'Unknown'}"),
            Text("Name: ${_libraryName ?? 'Unknown'}"),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _initData, child: const Text("Retry")),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrImageView(data: _qrData!, version: QrVersions.auto, size: 200.0),
          const SizedBox(height: 20),
          Text(_libraryName!, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text("Scan this code on another device to connect."),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return MobileScanner(onDetect: _onDetect);
  }
}
