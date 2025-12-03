import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Service to manage the bundled Rust backend process
class BackendService {
  Process? _process;
  int? _port;
  bool _isRunning = false;
  Timer? _healthCheckTimer;

  bool get isRunning => _isRunning;
  int? get port => _port;

  /// Start the bundled backend process
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('Backend already running on port $_port');
      return;
    }

    try {
      // Get path to bundled binary
      final backendPath = await _getBackendBinaryPath();
      
      debugPrint('Starting backend from: $backendPath');

      // Set environment variables
      final env = {
        'PORT': '8001', // Preferred port (will auto-detect if taken)
        'DATABASE_URL': await _getDatabasePath(),
        'HUB_URL': 'http://localhost:8081', // Optional Hub
        'RUST_LOG': 'info',
      };

      // Start backend process
      _process = await Process.start(
        backendPath,
        [],
        environment: env,
        runInShell: false,
      );

      // Listen to stdout/stderr
      _process!.stdout.transform(SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend] $data');
      });

      _process!.stderr.transform(SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend Error] $data');
      });

      // Wait for backend to write port file
      await _waitForPort();

      _isRunning = true;
      debugPrint('Backend started successfully on port $_port');

      // Start health monitoring
      _startHealthCheck();
    } catch (e) {
      debugPrint('Failed to start backend: $e');
      rethrow;
    }
  }

  /// Stop the backend process gracefully
  Future<void> stop() async {
    if (!_isRunning || _process == null) {
      return;
    }

    debugPrint('Stopping backend...');

    // Stop health check
    _healthCheckTimer?.cancel();

    try {
      // Send SIGTERM for graceful shutdown
      _process!.kill(ProcessSignal.sigterm);

      // Wait for exit (with timeout)
      await _process!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Backend did not stop gracefully, forcing kill');
          _process!.kill(ProcessSignal.sigkill);
          return _process!.exitCode;
        },
      );

      debugPrint('Backend stopped');
    } catch (e) {
      debugPrint('Error stopping backend: $e');
    } finally {
      _process = null;
      _port = null;
      _isRunning = false;
    }
  }

  /// Restart the backend
  Future<void> restart() async {
    await stop();
    await Future.delayed(const Duration(seconds: 1));
    await start();
  }

  /// Get the path to the bundled backend binary
  Future<String> _getBackendBinaryPath() async {
    if (Platform.isMacOS) {
      // In bundled app: BiblioGenius.app/Contents/MacOS/BiblioGenius (executable)
      // Backend is in: BiblioGenius.app/Contents/Resources/backend/bibliogenius
      
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      // Go up one level from MacOS to Contents, then down to Resources
      final backendPath = path.join(executableDir, '..', 'Resources', 'backend', 'bibliogenius');
      final absoluteBackendPath = path.normalize(backendPath);
      
      debugPrint('Resolved backend path: $absoluteBackendPath');
      
      if (!await File(backendPath).exists()) {
        throw Exception(
          'Backend binary not found at $backendPath. '
          'Make sure to bundle the Rust backend in the app.',
        );
      }
      
      return backendPath;
    } else {
      throw UnsupportedError('Backend bundling only supported on macOS for now');
    }
  }

  /// Get the database path
  Future<String> _getDatabasePath() async {
    if (Platform.isMacOS) {
      // ~/Library/Application Support/BiblioGenius/bibliogenius.db
      final home = Platform.environment['HOME']!;
      final appSupport = path.join(home, 'Library', 'Application Support', 'BiblioGenius');
      
      // Create directory if it doesn't exist
      await Directory(appSupport).create(recursive: true);
      
      return 'sqlite://${path.join(appSupport, 'bibliogenius.db')}?mode=rwc';
    } else if (Platform.isLinux) {
      // ~/.local/share/bibliogenius/bibliogenius.db
      final home = Platform.environment['HOME']!;
      final dataDir = path.join(home, '.local', 'share', 'bibliogenius');
      
      await Directory(dataDir).create(recursive: true);
      
      return 'sqlite://${path.join(dataDir, 'bibliogenius.db')}?mode=rwc';
    } else if (Platform.isWindows) {
      // %LOCALAPPDATA%\BiblioGenius\bibliogenius.db
      final appData = Platform.environment['LOCALAPPDATA']!;
      final dataDir = path.join(appData, 'BiblioGenius');
      
      await Directory(dataDir).create(recursive: true);
      
      return 'sqlite://${path.join(dataDir, 'bibliogenius.db')}?mode=rwc';
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Wait for the backend to write the port file
  Future<void> _waitForPort({int maxAttempts = 30}) async {
    final portFilePath = _getPortFilePath();
    
    for (var i = 0; i < maxAttempts; i++) {
      final portFile = File(portFilePath);
      
      if (await portFile.exists()) {
        try {
          final portStr = await portFile.readAsString();
          _port = int.parse(portStr.trim());
          debugPrint('Backend port detected: $_port');
          return;
        } catch (e) {
          debugPrint('Error reading port file: $e');
        }
      }
      
      // Wait before next attempt
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    throw TimeoutException('Backend did not write port file within 3 seconds');
  }

  /// Get the path to the port file
  String _getPortFilePath() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME']!;
      return path.join(home, 'Library', 'Caches', 'BiblioGenius', 'backend_port.txt');
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME']!;
      return path.join(home, '.cache', 'bibliogenius', 'backend_port.txt');
    } else if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA']!;
      return path.join(appData, 'BiblioGenius', 'backend_port.txt');
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Start periodic health checks
  void _startHealthCheck() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final healthy = await checkHealth();
      
      if (!healthy) {
        debugPrint('Backend health check failed, restarting...');
        await restart();
      }
    });
  }

  /// Check if backend is healthy
  Future<bool> checkHealth() async {
    if (_port == null) return false;
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://localhost:$_port/api/health'));
      final response = await request.close();
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }
}
