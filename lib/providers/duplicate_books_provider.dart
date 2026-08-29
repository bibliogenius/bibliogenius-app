import 'package:flutter/foundation.dart';

import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' as frb;

/// Duplicate-book preview and merge (ADR-070).
///
/// Two devices that each held the same book before they shared an account
/// minted two uuids for it, and cr-sqlite merges by primary key, so the joined
/// library carries both rows. This provider drives the maintenance screen that
/// repairs it: a preview that writes nothing, then a merge the reader confirms.
///
/// Not a singleton: the screen owns one, so leaving it drops the preview
/// instead of keeping a stale group list alive behind the reader's back.
class DuplicateBooksProvider extends ChangeNotifier {
  DuplicateBooksProvider({FfiService? ffi}) : _ffi = ffi ?? FfiService();

  final FfiService _ffi;

  frb.FrbDuplicateScan? _scan;
  bool _isScanning = false;
  bool _isMerging = false;
  String? _error;
  frb.FrbMergeReport? _lastReport;

  frb.FrbDuplicateScan? get scan => _scan;
  bool get isScanning => _isScanning;
  bool get isMerging => _isMerging;
  bool get isBusy => _isScanning || _isMerging;
  String? get error => _error;
  frb.FrbMergeReport? get lastReport => _lastReport;

  List<frb.FrbDuplicateGroup> get automatic => _scan?.automatic ?? const [];
  List<frb.FrbDuplicateGroup> get proposed => _scan?.proposed ?? const [];

  /// Book rows the automatic merge would remove.
  int get booksRemovedByAutomatic => _scan?.booksRemovedByAutomatic ?? 0;

  bool get hasAnything => automatic.isNotEmpty || proposed.isNotEmpty;

  /// Recompute the preview. Writes nothing, so it is safe on every entry.
  Future<void> refresh() async {
    _isScanning = true;
    _error = null;
    notifyListeners();
    try {
      _scan = await _ffi.scanDuplicateBooks();
    } catch (e) {
      _error = e.toString();
      debugPrint('DuplicateBooksProvider.refresh error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Merge every ISBN-correlated group, then refresh the preview.
  /// Returns whether the merge went through.
  Future<bool> mergeAutomatic() => _merge(() => _ffi.mergeDuplicateBooks());

  /// Merge one proposed group, then refresh the preview.
  Future<bool> mergeGroup(String key) =>
      _merge(() => _ffi.mergeDuplicateGroup(key));

  Future<bool> _merge(Future<frb.FrbMergeReport> Function() run) async {
    if (_isMerging) return false;
    _isMerging = true;
    _error = null;
    _lastReport = null;
    notifyListeners();
    try {
      _lastReport = await run();
      // The library changed underneath: re-read rather than patching the
      // groups locally, so the screen can never show a stale survivor.
      _scan = await _ffi.scanDuplicateBooks();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('DuplicateBooksProvider.merge error: $e');
      return false;
    } finally {
      _isMerging = false;
      notifyListeners();
    }
  }
}
