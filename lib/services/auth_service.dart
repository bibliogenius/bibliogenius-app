import 'dart:async' show Completer;
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, immutable, kDebugMode, visibleForTesting;
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
  static const _androidOptions = AndroidOptions(resetOnError: true);

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
      if (e.code == 'Unexpected security result code' ||
          e.message?.contains('-34018') == true) {
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
      if (e.code == 'Unexpected security result code' ||
          e.message?.contains('-34018') == true) {
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
      if (e.code == 'Unexpected security result code' ||
          e.message?.contains('-34018') == true) {
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

/// Outcome of reconciling the two macOS copies of `library_uuid`: the value to
/// converge on, plus which store(s) must be (re)written to match it.
@immutable
class LibraryUuidReconciliation {
  /// The UUID both stores should converge on, or `null` when neither store held
  /// a value (the caller must mint a fresh UUID).
  final String? chosen;

  /// The Keychain copy must be (re)written to match [chosen].
  final bool needsSecureWrite;

  /// The NSUserDefaults copy must be (re)written to match [chosen].
  final bool needsPrefsWrite;

  const LibraryUuidReconciliation({
    required this.chosen,
    this.needsSecureWrite = false,
    this.needsPrefsWrite = false,
  });
}

/// Reconcile the macOS Keychain ([secure]) and NSUserDefaults ([prefs]) copies
/// of `library_uuid` so they converge on a single value, preventing the silent
/// identity regeneration a Keychain <-> NSUserDefaults swing would otherwise
/// trigger (see `memory/e2ee_identity_storage_fragility.md`).
///
/// Rules (intentionally NON-DESTRUCTIVE — a populated store is never
/// overwritten with a different value):
/// - Both present and equal: use it, no writes.
/// - Both present but different (already mid-swing): use the Keychain copy for
///   this boot but write NOTHING. The NSUserDefaults copy may be the value that
///   actually decrypts `crypto_keys`; overwriting it could force an identity
///   wipe. A wrong pick instead surfaces `E_IDENTITY_DECRYPT_FAILED` from the
///   Rust layer for user-confirmed recovery, and the alternative value stays
///   available for a future attempt.
/// - Exactly one present: adopt it and mirror into the EMPTY store (safe fill).
/// - Neither present: [chosen] is null; the caller mints a fresh UUID and
///   writes both stores.
///
/// Empty strings are treated as absent.
@visibleForTesting
LibraryUuidReconciliation reconcileLibraryUuid(String? secure, String? prefs) {
  final hasSecure = secure != null && secure.isNotEmpty;
  final hasPrefs = prefs != null && prefs.isNotEmpty;

  if (hasSecure) {
    // Both present (equal or not): use Keychain, never clobber the prefs copy.
    if (hasPrefs) {
      return LibraryUuidReconciliation(chosen: secure);
    }
    // prefs empty: safe to fill it with the Keychain value.
    return LibraryUuidReconciliation(chosen: secure, needsPrefsWrite: true);
  }
  if (hasPrefs) {
    return LibraryUuidReconciliation(chosen: prefs, needsSecureWrite: true);
  }
  return const LibraryUuidReconciliation(chosen: null);
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

  // ============ Auto-backup passphrase (ADR-037 §6, mode 'passphrase') =====
  static const _autoBackupPassphraseKey = 'auto_backup_passphrase';

  /// Store the user-chosen passphrase used to encrypt auto-backup
  /// archives when [BackupSchedulerService.unlockMode] is `'passphrase'`.
  /// Distinct from the hub recovery code so a passphrase change here
  /// does not impact hub auth, and a hub re-pair does not silently
  /// rotate the auto-backup secret.
  Future<void> saveAutoBackupPassphrase(String passphrase) async {
    await storage.write(key: _autoBackupPassphraseKey, value: passphrase);
  }

  Future<String?> getAutoBackupPassphrase() async {
    return await storage.read(key: _autoBackupPassphraseKey);
  }

  Future<void> deleteAutoBackupPassphrase() async {
    await storage.delete(key: _autoBackupPassphraseKey);
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
      final String uuid;
      if (Platform.isMacOS && !kDebugMode) {
        // Release macOS is the only target exposed to the Keychain <->
        // NSUserDefaults swing, so reconcile both stores here. Debug macOS
        // deliberately stays on the prefs-only store (mirrors the kDebugMode
        // short-circuit in _createStorage, which avoids Keychain entitlement
        // issues without an Apple Developer account). iOS (reliable Keychain)
        // and Android (EncryptedSharedPreferences + resetOnError) keep the
        // single-secure-store path and gain no plaintext copy.
        uuid = await _resolveLibraryUuidMacOs();
      } else {
        var existing = await storage.read(key: _libraryUuidKey);
        if (existing == null) {
          existing = const Uuid().v4();
          await storage.write(key: _libraryUuidKey, value: existing);
        }
        uuid = existing;
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

  /// Read-only accessor for the device's existing `library_uuid`. Unlike
  /// [getOrCreateLibraryUuid], it NEVER mints a fresh UUID on a miss and NEVER
  /// writes to either store. Returns the persisted value, or `null` when the
  /// device genuinely has none.
  ///
  /// Used by the restore wizard so a transiently-dark store cannot make it mint
  /// a junk UUID mid-restore and wrongly flip the same-device detection into a
  /// destructive cross-device identity reset (ADR-042 §13.3,
  /// `e2ee_identity_storage_fragility.md`). On release macOS it consults BOTH
  /// stores (Keychain + NSUserDefaults) and returns whichever holds the value,
  /// so a single dark store does not look like "absent".
  Future<String?> peekLibraryUuid() async {
    // A value resolved earlier in this process is the real one; reuse it.
    if (_cachedUuid != null) return _cachedUuid;

    if (Platform.isMacOS && !kDebugMode) {
      final secure = await _readSecureLibraryUuid();
      final prefs = await _readPrefsLibraryUuid();
      // Reuse the converge rules WITHOUT performing any write: we only need the
      // chosen value, not the store-mirroring side effects.
      return reconcileLibraryUuid(secure, prefs).chosen;
    }

    try {
      final v = await storage.read(key: _libraryUuidKey);
      return (v != null && v.isNotEmpty) ? v : null;
    } catch (e) {
      debugPrint('peekLibraryUuid: read failed: $e');
      return null;
    }
  }

  /// macOS-only: resolve `library_uuid` from both stores and converge them so a
  /// future Keychain <-> NSUserDefaults swing cannot lose the value. Reuses
  /// [setLibraryUuidDualWrite] for the converging write. Best-effort: a store
  /// that is unreadable is treated as empty and reconciled from the other.
  Future<String> _resolveLibraryUuidMacOs() async {
    final secure = await _readSecureLibraryUuid();
    final prefs = await _readPrefsLibraryUuid();
    final r = reconcileLibraryUuid(secure, prefs);

    if (r.chosen != null && !r.needsSecureWrite && !r.needsPrefsWrite) {
      // Stores agree, or they diverge and we deliberately write nothing so the
      // non-chosen copy is preserved for recovery (see reconcileLibraryUuid).
      _cachedUuid = r.chosen;
      return r.chosen!;
    }
    final chosen = r.chosen ?? const Uuid().v4();
    // Fills the empty store / mints a fresh UUID into both. Never overwrites a
    // populated store with a different value (idempotent; per-store failures
    // are swallowed by setLibraryUuidDualWrite).
    await setLibraryUuidDualWrite(chosen);
    return chosen;
  }

  /// Reads `library_uuid` from the Keychain directly. Returns null on any
  /// failure (e.g. -34018 errSecMissingEntitlement) so the caller can fall back
  /// to the NSUserDefaults copy instead of throwing.
  Future<String?> _readSecureLibraryUuid() async {
    try {
      final v = await const FlutterSecureStorage().read(
        key: _libraryUuidKey,
        aOptions: const AndroidOptions(resetOnError: true),
      );
      return (v != null && v.isNotEmpty) ? v : null;
    } catch (e) {
      debugPrint('getOrCreateLibraryUuid: Keychain read failed: $e');
      return null;
    }
  }

  /// Reads the NSUserDefaults fallback copy of `library_uuid` (same key
  /// [setLibraryUuidDualWrite] writes). Returns null on any failure.
  Future<String?> _readPrefsLibraryUuid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('auth_fallback_$_libraryUuidKey');
      return (v != null && v.isNotEmpty) ? v : null;
    } catch (e) {
      debugPrint('getOrCreateLibraryUuid: prefs read failed: $e');
      return null;
    }
  }

  /// Resets the in-process `library_uuid` cache. Test-only: production never
  /// needs to clear it within a single process lifetime.
  @visibleForTesting
  static void resetLibraryUuidCacheForTest() {
    _cachedUuid = null;
    _uuidCompleter = null;
  }

  /// Adopt a library UUID from another device during P2P pairing.
  /// This overwrites the local UUID, effectively joining the source library.
  Future<void> setLibraryUuid(String uuid) async {
    await storage.write(key: _libraryUuidKey, value: uuid);
    _cachedUuid = uuid;
  }

  /// Write `library_uuid` to BOTH the secure store (Keychain on Apple,
  /// EncryptedSharedPreferences on Android) AND the SharedPreferences fallback
  /// (NSUserDefaults on Apple) explicitly.
  ///
  /// Used by the local-backup restore wizard (ADR-037 §5) to harden against
  /// the Keychain <-> NSUserDefaults storage swing documented in
  /// `e2ee_identity_storage_fragility.md`. Either store going dark on a
  /// future launch (DMG re-sign, -34018 transient, OS-level Keychain
  /// reshuffle) leaves the other one with the correct UUID, avoiding the
  /// silent identity-wipe that would otherwise break peer relationships.
  ///
  /// Idempotent: failures on one store are logged and swallowed so the other
  /// store still reflects the new UUID.
  Future<void> setLibraryUuidDualWrite(String uuid) async {
    try {
      await const FlutterSecureStorage().write(
        key: _libraryUuidKey,
        value: uuid,
        aOptions: const AndroidOptions(resetOnError: true),
      );
    } catch (e) {
      debugPrint('setLibraryUuidDualWrite: secure store write failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_fallback_$_libraryUuidKey', uuid);
    } catch (e) {
      debugPrint('setLibraryUuidDualWrite: prefs write failed: $e');
    }
    _cachedUuid = uuid;
  }

  /// Clear `library_uuid` from BOTH stores. Used by the restore wizard when
  /// the user picks the "do not restore identity" option, so the next launch
  /// hits the clean-install path and generates a fresh UUID.
  Future<void> clearLibraryUuidBothStores() async {
    try {
      await const FlutterSecureStorage().delete(
        key: _libraryUuidKey,
        aOptions: const AndroidOptions(resetOnError: true),
      );
    } catch (e) {
      debugPrint('clearLibraryUuidBothStores: secure store delete failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_fallback_$_libraryUuidKey');
    } catch (e) {
      debugPrint('clearLibraryUuidBothStores: prefs delete failed: $e');
    }
    _cachedUuid = null;
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
    await storage.delete(
      key: _hubWriteTokenKey,
    ); // Clear hub token on full reset
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
