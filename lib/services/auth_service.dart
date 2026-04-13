import 'dart:async' show Completer;
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;

abstract class SecureStorageInterface {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

class RealSecureStorage implements SecureStorageInterface {
  // On Android, resetOnError: true auto-resets EncryptedSharedPreferences
  // when the Keystore key is invalidated (e.g., after app reinstall with
  // Auto Backup restoring encrypted data but not the Keystore key).
  // Data is lost but was unreadable anyway; the app will re-create tokens.
  static const _androidOptions = AndroidOptions(
    resetOnError: true,
  );

  final _storage = const FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value, aOptions: _androidOptions);
  @override
  Future<String?> read({required String key}) =>
      _storage.read(key: key, aOptions: _androidOptions);
  @override
  Future<void> delete({required String key}) =>
      _storage.delete(key: key, aOptions: _androidOptions);
}

/// Wraps [RealSecureStorage] and automatically falls back to
/// [SharedPreferencesStorage] when the Keychain is unavailable.
/// This happens on macOS DMG builds (hardened runtime, no sandbox,
/// no keychain-access-groups entitlement -> errSecMissingEntitlement -34018).
/// On Android, Keystore issues are handled by AndroidOptions(resetOnError: true)
/// in [RealSecureStorage] instead, keeping data encrypted.
class ResilientSecureStorage implements SecureStorageInterface {
  SecureStorageInterface _delegate = RealSecureStorage();
  bool _didFallback = false;

  void _fallback() {
    if (!_didFallback) {
      _didFallback = true;
      _delegate = SharedPreferencesStorage();
      debugPrint('⚠️ Keychain unavailable, using SharedPreferences fallback');
    }
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    try {
      await _delegate.write(key: key, value: value);
    } on PlatformException catch (e) {
      if (e.code == 'Unexpected security result code' || e.message?.contains('-34018') == true) {
        _fallback();
        await _delegate.write(key: key, value: value);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _delegate.read(key: key);
    } on PlatformException catch (e) {
      if (e.code == 'Unexpected security result code' || e.message?.contains('-34018') == true) {
        _fallback();
        return await _delegate.read(key: key);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _delegate.delete(key: key);
    } on PlatformException catch (e) {
      if (e.code == 'Unexpected security result code' || e.message?.contains('-34018') == true) {
        _fallback();
        await _delegate.delete(key: key);
      } else {
        rethrow;
      }
    }
  }
}

/// Fallback storage using SharedPreferences for macOS debug builds
/// WARNING: Not secure for production - data is stored in plain text
class SharedPreferencesStorage implements SecureStorageInterface {
  static const _prefix = 'auth_fallback_';

  @override
  Future<void> write({required String key, required String? value}) async {
    final prefs = await SharedPreferences.getInstance();
    if (value != null) {
      await prefs.setString('$_prefix$key', value);
    } else {
      await prefs.remove('$_prefix$key');
    }
  }

  @override
  Future<String?> read({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> delete({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}

class MockSecureStorage implements SecureStorageInterface {
  final Map<String, String> _data = {};
  @override
  Future<void> write({required String key, required String? value}) async =>
      _data[key] = value!;
  @override
  Future<String?> read({required String key}) async => _data[key];
  @override
  Future<void> delete({required String key}) async => _data.remove(key);
}

class AuthService {
  // Use SharedPreferences fallback on macOS debug to avoid keychain issues
  static SecureStorageInterface storage = _createStorage();

  static SecureStorageInterface _createStorage() {
    if (kDebugMode && Platform.isMacOS) {
      // Use SharedPreferences fallback on macOS debug builds
      // This avoids keychain entitlement issues without Apple Developer account
      return SharedPreferencesStorage();
    }
    if (Platform.isMacOS) {
      // DMG builds have hardened runtime but no keychain entitlement.
      // ResilientSecureStorage tries Keychain first, falls back to
      // SharedPreferences on -34018 (errSecMissingEntitlement).
      return ResilientSecureStorage();
    }
    return RealSecureStorage();
  }

  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'username';
  static const _userIdKey = 'user_id';
  static const _libraryIdKey = 'library_id';

  Future<void> saveToken(String token) async {
    await storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await storage.read(key: _tokenKey);
  }

  Future<void> saveUsername(String username) async {
    await storage.write(key: _usernameKey, value: username);
  }

  Future<String?> getUsername() async {
    return await storage.read(key: _usernameKey);
  }

  Future<void> saveUserId(int id) async {
    await storage.write(key: _userIdKey, value: id.toString());
  }

  Future<int?> getUserId() async {
    final str = await storage.read(key: _userIdKey);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> saveLibraryId(int id) async {
    await storage.write(key: _libraryIdKey, value: id.toString());
  }

  Future<int?> getLibraryId() async {
    final str = await storage.read(key: _libraryIdKey);
    return str != null ? int.tryParse(str) : null;
  }

  // ============ Hub Write Token (Keychain backup for reinstall recovery) ===
  static const _hubWriteTokenKey = 'hub_write_token';
  static const _hubRecoveryCodeKey = 'hub_recovery_code';

  /// Back up the hub write_token to Keychain so it survives reinstalls.
  Future<void> saveHubWriteToken(String token) async {
    await storage.write(key: _hubWriteTokenKey, value: token);
  }

  /// Retrieve the hub write_token from Keychain (post-reinstall recovery).
  Future<String?> getHubWriteToken() async {
    return await storage.read(key: _hubWriteTokenKey);
  }

  /// Delete only the hub write_token from Keychain (401 recovery).
  Future<void> deleteHubWriteToken() async {
    await storage.delete(key: _hubWriteTokenKey);
  }

  /// Back up the hub recovery_code to Keychain. Must survive config purges
  /// so the user can reclaim their profile after token invalidation.
  Future<void> saveHubRecoveryCode(String code) async {
    await storage.write(key: _hubRecoveryCodeKey, value: code);
  }

  /// Retrieve the hub recovery_code from Keychain (e.g. to recover a stale
  /// profile when the local config was purged).
  Future<String?> getHubRecoveryCode() async {
    return await storage.read(key: _hubRecoveryCodeKey);
  }

  /// Delete the recovery_code from Keychain. Only call on explicit user
  /// opt-out (e.g. account deletion); never during 401 recovery.
  Future<void> deleteHubRecoveryCode() async {
    await storage.delete(key: _hubRecoveryCodeKey);
  }

  // ============ Library UUID (for P2P deduplication) ============
  static const _libraryUuidKey = 'library_uuid';

  /// In-memory cache to avoid concurrent reads generating different UUIDs.
  /// Prevents TOCTOU race when multiple callers invoke getOrCreateLibraryUuid
  /// before the first write has flushed to storage.
  static String? _cachedUuid;
  static Completer<String>? _uuidCompleter;

  /// Get or create a stable UUID for this library instance.
  /// This UUID persists across app restarts and is used for P2P peer deduplication.
  /// Thread-safe: concurrent callers wait on the same Completer.
  Future<String> getOrCreateLibraryUuid() async {
    // Fast path: already resolved in this process
    if (_cachedUuid != null) return _cachedUuid!;

    // Serialize concurrent callers: only the first one does the read/write
    if (_uuidCompleter != null) return _uuidCompleter!.future;
    _uuidCompleter = Completer<String>();

    try {
      var uuid = await storage.read(key: _libraryUuidKey);
      if (uuid == null) {
        uuid = const Uuid().v4();
        await storage.write(key: _libraryUuidKey, value: uuid);
      }
      _cachedUuid = uuid;
      _uuidCompleter!.complete(uuid);
      return uuid;
    } catch (e) {
      _uuidCompleter!.completeError(e);
      _uuidCompleter = null;
      rethrow;
    }
  }

  /// Adopt a library UUID from another device during P2P pairing.
  /// This overwrites the local UUID, effectively joining the source library.
  Future<void> setLibraryUuid(String uuid) async {
    await storage.write(key: _libraryUuidKey, value: uuid);
    _cachedUuid = uuid;
  }

  Future<void> logout() async {
    await storage.delete(key: _tokenKey);
    await storage.delete(key: _usernameKey);
    await storage.delete(key: _userIdKey);
    await storage.delete(key: _libraryIdKey);
  }

  /// Clear ALL auth data including password (for complete reset)
  /// Use this for "Reset Entirely" to emulate fresh install
  Future<void> clearAll() async {
    await storage.delete(key: _tokenKey);
    await storage.delete(key: _usernameKey);
    await storage.delete(key: _userIdKey);
    await storage.delete(key: _libraryIdKey);
    await storage.delete(key: _libraryUuidKey); // Regenerate UUID on full reset
    await storage.delete(key: _hubWriteTokenKey); // Clear hub token on full reset
    await storage.delete(key: _passwordKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  // ============ Password Management (Local Mode) ============
  static const _passwordKey = 'local_password_hash';

  /// Save password locally (stores a simple hash for verification)
  /// Note: Uses a simple hash since this is local-only protection
  Future<void> savePassword(String password) async {
    final hash = _simpleHash(password);
    await storage.write(key: _passwordKey, value: hash);
  }

  /// Verify password against stored hash
  Future<bool> verifyPassword(String password) async {
    final storedHash = await storage.read(key: _passwordKey);
    if (storedHash == null) {
      // No password set - allow access (first-time setup)
      return true;
    }
    return _simpleHash(password) == storedHash;
  }

  /// Check if a password has been set
  Future<bool> hasPasswordSet() async {
    final storedHash = await storage.read(key: _passwordKey);
    return storedHash != null;
  }

  /// Change password (requires old password verification)
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    final isValid = await verifyPassword(oldPassword);
    if (!isValid) return false;
    await savePassword(newPassword);
    return true;
  }

  /// Remove password (requires current password verification)
  Future<bool> removePassword(String currentPassword) async {
    final isValid = await verifyPassword(currentPassword);
    if (!isValid) return false;
    await storage.delete(key: _passwordKey);
    return true;
  }

  /// Simple hash function for local password storage
  /// This is NOT cryptographically secure but sufficient for local-only protection
  String _simpleHash(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash) + input.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // Convert to 32bit integer
    }
    return hash.toRadixString(16);
  }
}
