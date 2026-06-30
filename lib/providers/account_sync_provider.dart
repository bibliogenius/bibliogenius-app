import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/ffi_service.dart';

/// Signed-in status of the multi-device account on THIS device. Plaintext
/// metadata only (the trousseau is never exposed to Dart).
@immutable
class AccountStatus {
  final bool signedIn;
  final String email;
  final String accountId;
  final String deviceId;

  const AccountStatus({
    required this.signedIn,
    required this.email,
    required this.accountId,
    required this.deviceId,
  });

  const AccountStatus.signedOut()
    : signedIn = false,
      email = '',
      accountId = '',
      deviceId = '';

  factory AccountStatus.fromJson(Map<String, dynamic> j) => AccountStatus(
    signedIn: j['signed_in'] == true,
    email: (j['email'] as String?) ?? '',
    accountId: (j['account_id'] as String?) ?? '',
    deviceId: (j['device_id'] as String?) ?? '',
  );
}

/// Result of the local passphrase strength check (zxcvbn). `acceptable` is the
/// hard gate the signup button enforces (zxcvbn 4/4 AND length >= 12).
@immutable
class PassphraseStrength {
  final int score; // 0..4
  final int length;
  final bool acceptable;
  final String? warning;
  final List<String> suggestions;

  const PassphraseStrength({
    required this.score,
    required this.length,
    required this.acceptable,
    required this.warning,
    required this.suggestions,
  });

  const PassphraseStrength.empty()
    : score = 0,
      length = 0,
      acceptable = false,
      warning = null,
      suggestions = const [];

  factory PassphraseStrength.fromJson(Map<String, dynamic> j) =>
      PassphraseStrength(
        score: (j['score'] as num?)?.toInt() ?? 0,
        length: (j['length'] as num?)?.toInt() ?? 0,
        acceptable: j['acceptable'] == true,
        warning: (j['warning'] as String?)?.isEmpty ?? true
            ? null
            : j['warning'] as String,
        suggestions:
            (j['suggestions'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

/// One authorized device in the account's signed registry.
@immutable
class AccountDevice {
  final String deviceId;
  final String name;
  final bool isSelf;

  const AccountDevice({
    required this.deviceId,
    required this.name,
    required this.isSelf,
  });

  factory AccountDevice.fromJson(Map<String, dynamic> j) => AccountDevice(
    deviceId: (j['device_id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    isSelf: j['is_self'] == true,
  );
}

/// Outcome of a successful signup: the new status plus the one-time BIP39
/// recovery phrase to display ONCE (never persisted, never re-fetchable).
@immutable
class AccountSignupResult {
  final AccountStatus status;
  final String recoveryPhrase;

  /// Data sync activates only after an app restart (the backend CRR-ifies the
  /// database on the next launch, see `account_sync_restart_dialog`).
  final bool restartRequired;

  const AccountSignupResult({
    required this.status,
    required this.recoveryPhrase,
    required this.restartRequired,
  });
}

/// Raised when signup fails in a way the UI can recover from. `accountExists`
/// means the email is already registered (offer "sign in" / join-with-passphrase);
/// `weakPassphrase` is a backstop for the local strength gate being bypassed.
class AccountSignupException implements Exception {
  final bool accountExists;
  final bool weakPassphrase;
  final String message;

  const AccountSignupException(
    this.message, {
    this.accountExists = false,
    this.weakPassphrase = false,
  });

  @override
  String toString() => message;
}

/// State manager for the multi-device account sync feature.
///
/// Centralizes every account FFI call (via [FfiService]) and the JSON parsing,
/// exposing typed state to the UI. The unlocked trousseau lives only in Rust;
/// this layer sees plaintext metadata, the live strength meter, the device
/// list, and the one-time recovery phrase.
class AccountSyncProvider extends ChangeNotifier {
  AccountSyncProvider({FfiService? ffi}) : _ffi = ffi ?? FfiService();

  final FfiService _ffi;

  AccountStatus _status = const AccountStatus.signedOut();
  List<AccountDevice> _devices = const [];
  bool _busy = false;
  String? _error;
  bool _autoSyncInFlight = false;

  AccountStatus get status => _status;
  bool get signedIn => _status.signedIn;
  List<AccountDevice> get devices => List.unmodifiable(_devices);
  bool get busy => _busy;
  String? get error => _error;

  /// Refresh the cheap signed-in status (no decrypt, no network).
  Future<void> refreshStatus() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _status = AccountStatus.fromJson(
        jsonDecode(await _ffi.accountStatus()) as Map<String, dynamic>,
      );
      if (!_status.signedIn) _devices = const [];
    } catch (e) {
      _error = e.toString();
      debugPrint('AccountSyncProvider.refreshStatus error: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Score a candidate passphrase for the live signup meter. Pure: no state
  /// mutation, debounce on the caller side. Returns an empty score for blanks.
  Future<PassphraseStrength> checkPassphrase(String passphrase) async {
    if (passphrase.isEmpty) return const PassphraseStrength.empty();
    final json = await _ffi.accountCheckPassphrase(passphrase);
    return PassphraseStrength.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
  }

  /// Create a NEW account on this device. On success updates [status] and
  /// returns the one-time recovery phrase. Throws [AccountSignupException] with
  /// `accountExists` when the email is already taken so the UI can offer to
  /// sign in instead.
  Future<AccountSignupResult> signup({
    required String email,
    required String passphrase,
    required String deviceName,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final json = await _ffi.accountSignup(
        email: email,
        passphrase: passphrase,
        deviceName: deviceName,
      );
      final map = jsonDecode(json) as Map<String, dynamic>;
      _status = AccountStatus.fromJson(map);
      return AccountSignupResult(
        status: _status,
        recoveryPhrase: (map['recovery_phrase'] as String?) ?? '',
        restartRequired: map['restart_required'] == true,
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('E_ACCOUNT_EXISTS')) {
        throw AccountSignupException(msg, accountExists: true);
      }
      if (msg.contains('E_WEAK_PASSPHRASE')) {
        throw AccountSignupException(msg, weakPassphrase: true);
      }
      _error = msg;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Join an EXISTING account on this device with its passphrase (Path A).
  /// Returns whether an app restart is required to activate data sync.
  Future<bool> joinWithPassphrase({
    required String email,
    required String passphrase,
    required String deviceName,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final map =
          jsonDecode(
                await _ffi.accountEnrollPassphrase(
                  email: email,
                  passphrase: passphrase,
                  deviceName: deviceName,
                ),
              )
              as Map<String, dynamic>;
      _status = AccountStatus.fromJson(map);
      return map['restart_required'] == true;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// NEW device, step 1: this device's `bg-pair` QR payload (carries no secret).
  Future<String> getDevicePairingQr(String deviceName) =>
      _ffi.accountGetDevicePairingQr(deviceName);

  /// AUTHORIZED device: seal the trousseau to a scanned `bg-pair` payload and
  /// register the device. Returns the `bg-sealed` payload to show back as a QR.
  /// Refreshes the device list afterwards so the new device appears.
  Future<String> authorizeDevice(String pairingQrPayload) async {
    final sealed = await _ffi.accountAuthorizeDevice(pairingQrPayload);
    await refreshDevices();
    return sealed;
  }

  /// NEW device, step 2: open a scanned `bg-sealed` payload and persist the
  /// session on this device. Returns whether an app restart is required to
  /// activate data sync.
  Future<bool> enrollFromSealed(String sealedQrPayload) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final map =
          jsonDecode(await _ffi.accountEnrollFromSealed(sealedQrPayload))
              as Map<String, dynamic>;
      _status = AccountStatus.fromJson(map);
      return map['restart_required'] == true;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Fetch and adopt the signed device registry (H3), updating [devices].
  Future<void> refreshDevices() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final map =
          jsonDecode(await _ffi.accountRefreshDevices())
              as Map<String, dynamic>;
      final list = (map['devices'] as List?) ?? const [];
      _devices = list
          .map((e) => AccountDevice.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      _error = e.toString();
      debugPrint('AccountSyncProvider.refreshDevices error: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Run one sync cycle now (manual trigger). Returns the raw status JSON from
  /// the backend so the caller can surface a summary; refreshes the device list
  /// afterwards. On default (non-account-sync) builds the data leg is a no-op.
  Future<String> syncNow() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _ffi.accountSyncNow();
      await refreshDevices();
      return result;
    } catch (e) {
      _error = e.toString();
      debugPrint('AccountSyncProvider.syncNow error: $e');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Whether this build can converge data across devices (the `account_sync`
  /// Cargo feature is compiled in). Used by the auto-sync scheduler to stay
  /// inert on default builds, where the data leg is a no-op.
  Future<bool> accountSyncCapable() => _ffi.accountSyncCapable();

  /// Quiet auto-sync tick driven by the background scheduler (periodic / on
  /// resume). Unlike [syncNow] it deliberately does NOT flip the [busy] spinner
  /// or surface failures to [error]: an automatic sync must be invisible, and a
  /// network failure (e.g. the hub is down) must stay silent. Re-entrant calls
  /// are coalesced so two triggers cannot run a cycle on the single-connection
  /// pool at once. No-ops when not signed in. Returns true if a cycle ran (the
  /// hub was reachable), false if it was skipped or failed silently.
  Future<bool> autoSyncTick() async {
    if (_autoSyncInFlight || !signedIn) return false;
    _autoSyncInFlight = true;
    try {
      await _ffi.accountSyncNow();
      return true;
    } catch (e) {
      // Silent by design: do not set _error or notify; just trace it.
      debugPrint('AccountSyncProvider.autoSyncTick (silent) error: $e');
      return false;
    } finally {
      _autoSyncInFlight = false;
    }
  }

  /// Sign out on this device: drop the session and clear local state.
  Future<void> logout() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _ffi.accountLogout();
      _status = const AccountStatus.signedOut();
      _devices = const [];
    } catch (e) {
      _error = e.toString();
      debugPrint('AccountSyncProvider.logout error: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
