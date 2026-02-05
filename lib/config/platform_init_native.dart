import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../src/rust/frb_generated.dart';
import '../src/rust/api/frb.dart' as frb;

const _migrationFlag = 'db_migration_completed_v1';
const _dbName = 'bibliogenius.db';
const _companionExtensions = ['-wal', '-shm', '-journal'];

/// Initializes the platform-specific dependencies.
/// For native platforms, this sets up the Rust FFI connection.
Future<bool> initializePlatform() async {
  try {
    debugPrint('FFI: Starting RustLib.init()...');
    if (Platform.isIOS || Platform.isMacOS) {
      debugPrint('FFI: Using DynamicLibrary.process() for iOS/macOS...');
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
    } else {
      await RustLib.init();
    }
    debugPrint('FFI: RustLib.init() succeeded');

    // Resolve database path (with auto-migration from Documents → Application Support)
    final dbPath = await _resolveDatabasePath();
    debugPrint('FFI: Database path: $dbPath');

    // Initialize Rust backend with database
    debugPrint('FFI: Calling initBackend...');
    final result = await frb.initBackend(dbPath: dbPath);
    debugPrint('FFI Backend initialized: $result');
    debugPrint('FFI: useFfi set to TRUE');

    return true; // useFfi = true
  } catch (e) {
    debugPrint('FFI Initialization Error: $e');
    return false;
  }
}

/// Resolves the database path, migrating from Documents to Application Support
/// if an old database exists at the legacy location.
Future<String> _resolveDatabasePath() async {
  final prefs = await SharedPreferences.getInstance();

  // Fast path: migration already completed
  if (prefs.getBool(_migrationFlag) == true) {
    final appSupportDir = await getApplicationSupportDirectory();
    final newPath = '${appSupportDir.path}/$_dbName';
    debugPrint('DB Migration: Already completed, using $newPath');
    return newPath;
  }

  // Resolve both paths
  final appDocDir = await getApplicationDocumentsDirectory();
  final appSupportDir = await getApplicationSupportDirectory();
  final oldPath = '${appDocDir.path}/$_dbName';
  final newPath = '${appSupportDir.path}/$_dbName';

  debugPrint('DB Migration: Old path: $oldPath');
  debugPrint('DB Migration: New path: $newPath');

  // If paths are identical (possible on some Linux configs), just set the flag
  if (oldPath == newPath) {
    debugPrint('DB Migration: Paths are identical, no migration needed');
    await prefs.setBool(_migrationFlag, true);
    return newPath;
  }

  final oldExists = File(oldPath).existsSync();
  final newExists = File(newPath).existsSync();

  if (oldExists) {
    // Old DB exists — always migrate it to new path (overwriting any
    // pre-existing DB at new path, which may be from standalone Rust binary)
    debugPrint('DB Migration: Migrating from old to new path...');
    final success = await _migrateDatabase(oldPath, newPath);
    if (success) {
      debugPrint('DB Migration: Migration successful');
      await _deleteOldFiles(oldPath);
      await prefs.setBool(_migrationFlag, true);
      return newPath;
    } else {
      // Migration failed — fall back to old path
      debugPrint('DB Migration: Migration failed, falling back to old path');
      return oldPath;
    }
  }

  // No old DB — use new path (may already exist from standalone Rust, or fresh install)
  if (newExists) {
    debugPrint('DB Migration: No old DB, using existing DB at new path');
  } else {
    debugPrint('DB Migration: Fresh install, using new path');
  }
  await prefs.setBool(_migrationFlag, true);
  return newPath;
}

/// Copies the database and companion files (WAL, SHM, journal) to the new location.
/// Returns true if the main DB file was copied and verified successfully.
Future<bool> _migrateDatabase(String oldPath, String newPath) async {
  try {
    // Ensure target directory exists
    final targetDir = File(newPath).parent;
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    // Copy main DB file
    final oldFile = File(oldPath);
    await oldFile.copy(newPath);

    // Verify copy
    final newFile = File(newPath);
    if (!newFile.existsSync() || newFile.lengthSync() != oldFile.lengthSync()) {
      debugPrint('DB Migration: Verification failed — size mismatch');
      // Clean up partial copy
      try {
        newFile.deleteSync();
      } catch (_) {}
      return false;
    }

    // Copy companion files (best-effort)
    for (final ext in _companionExtensions) {
      final companion = File('$oldPath$ext');
      if (companion.existsSync()) {
        try {
          await companion.copy('$newPath$ext');
          debugPrint('DB Migration: Copied companion $ext');
        } catch (e) {
          debugPrint('DB Migration: Failed to copy companion $ext: $e');
        }
      }
    }

    return true;
  } catch (e) {
    debugPrint('DB Migration: Copy failed: $e');
    // Clean up partial copy
    try {
      File(newPath).deleteSync();
    } catch (_) {}
    return false;
  }
}

/// Deletes old database and companion files. Failures are non-fatal.
Future<void> _deleteOldFiles(String oldPath) async {
  for (final suffix in ['', ..._companionExtensions]) {
    try {
      final file = File('$oldPath$suffix');
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint('DB Migration: Deleted old file $oldPath$suffix');
      }
    } catch (e) {
      debugPrint('DB Migration: Failed to delete $oldPath$suffix: $e');
    }
  }
}
