import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' show FrbReader;

/// Who reads on this device, and who else could.
///
/// Readers belong to the account and travel with it; the device only holds
/// which one reads here. With no reader chosen the device shows the shared
/// reading state, exactly as before readers existed. FFI only: the HTTP door
/// has no readers, and [load] simply leaves the list empty there.
class HouseholdProvider extends ChangeNotifier {
  HouseholdProvider({FfiService? ffi}) : _ffi = ffi ?? FfiService();

  final FfiService _ffi;

  /// Set when the user stepped back to the shared view on purpose: the
  /// invitation to pick a reader must not come back until they pick one.
  static const _keySharedViewChosen = 'household_shared_view_chosen';

  List<FrbReader> _readers = const [];
  String? _currentReaderId;
  bool _sharedViewChosen = false;
  bool _busy = false;
  bool _loaded = false;

  /// Every reader of the account, oldest first.
  List<FrbReader> get readers => _readers;

  String? get currentReaderId => _currentReaderId;

  FrbReader? get currentReader {
    for (final reader in _readers) {
      if (reader.id == _currentReaderId) return reader;
    }
    return null;
  }

  bool get busy => _busy;
  bool get isLoaded => _loaded;

  /// Readers exist on the account but none reads on this device yet: the
  /// other devices chose theirs, this one is still on the shared state and
  /// never said it wanted to stay there.
  bool get needsReaderChoice =>
      _readers.isNotEmpty && _currentReaderId == null && !_sharedViewChosen;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sharedViewChosen = prefs.getBool(_keySharedViewChosen) ?? false;
    } catch (_) {
      // Preferences unavailable: the invitation may show once more.
    }
    try {
      final readers = await _ffi.listHouseholdReaders();
      final current = await _ffi.getCurrentHouseholdReader();
      _readers = readers;
      _currentReaderId = current?.id;
    } catch (_) {
      // Readers are optional: a failure leaves the device on the shared
      // state and the section empty, never breaks the screens around it.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Adds a reader and makes them the reader of this device.
  Future<bool> createReader(String name) => _run(() async {
    await _ffi.createHouseholdReader(name);
    await _rememberSharedViewChosen(false);
  });

  Future<bool> selectReader(String readerId) => _run(() async {
    await _ffi.setCurrentHouseholdReader(readerId);
    await _rememberSharedViewChosen(false);
  });

  /// Back to the shared reading state. Readers and their readings are kept.
  Future<bool> leaveReader() => _run(() async {
    await _ffi.clearCurrentHouseholdReader();
    await _rememberSharedViewChosen(true);
  });

  Future<void> _rememberSharedViewChosen(bool chosen) async {
    _sharedViewChosen = chosen;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keySharedViewChosen, chosen);
    } catch (_) {
      // Kept in memory for this session at least.
    }
  }

  Future<bool> renameReader(String readerId, String name) =>
      _run(() => _ffi.renameHouseholdReader(readerId, name));

  /// Runs one change, then reloads. False when the backend refused it; the
  /// list is reloaded either way so the screen shows what actually holds.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    var ok = true;
    try {
      await action();
    } catch (_) {
      ok = false;
    }
    await load();
    _busy = false;
    notifyListeners();
    return ok;
  }
}
