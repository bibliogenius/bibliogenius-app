// Bulk metadata gap-fill provider (ADR-041) - "Compléter ma bibliothèque".
//
// Presentation-only state holder. All data decisions (what to fill, throttle,
// undo safety rule) live in the Rust backend; this provider just calls the FFI
// surface, polls progress while a run is active, and exposes typed state for
// the completeness card, progress sheet, recent-undo list and no-ISBN list.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' as frb;

class MetadataFillProvider extends ChangeNotifier {
  MetadataFillProvider({FfiService? ffi}) : _ffi = ffi ?? FfiService();

  final FfiService _ffi;

  frb.FrbCompletenessStats? _stats;
  frb.FrbFillProgress? _progress;
  List<frb.FrbFilledBook> _recent = const [];
  List<frb.FrbIncompleteBookDetail> _incomplete = const [];
  bool _loadingStats = false;
  bool _starting = false;
  String? _error;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Cumulative `done` at the moment the current lot started, so the run bar can
  /// show progress *within this lot* rather than across the whole backlog.
  int _lotStartDone = 0;

  /// Size of the current lot (null = "Tout" → the bar tracks the whole run).
  int? _lotSize;

  frb.FrbCompletenessStats? get stats => _stats;
  frb.FrbFillProgress? get progress => _progress;
  List<frb.FrbFilledBook> get recent => _recent;
  List<frb.FrbIncompleteBookDetail> get incomplete => _incomplete;
  bool get loadingStats => _loadingStats;
  bool get starting => _starting;
  String? get error => _error;

  /// A run is actively processing books right now.
  bool get isRunning => _progress?.status == 'running';

  /// A run was interrupted (killed/restarted) and can be resumed.
  bool get isResumable => _progress?.status == 'interrupted';

  /// The last run finished (completed or cancelled): show its result summary.
  bool get isFinished {
    final s = _progress?.status;
    return s == 'done' || s == 'cancelled';
  }

  /// The last run finished by completing the work — worth keeping a summary for.
  /// A *cancelled* run is excluded: the user abandoned it, so the UI returns to
  /// a clean start state rather than pinning the cancelled-run summary.
  bool get isCompleted => _progress?.status == 'done';

  /// Total empty gap-fill fields across owned books (field-level progress).
  int get emptyFields => _stats?.emptyFields.toInt() ?? 0;

  /// Number of owned books still missing at least one field, with an ISBN
  /// (the processable backlog).
  int get processableCount {
    final s = _stats;
    if (s == null) return 0;
    final v = s.incomplete - s.noIsbn;
    return v < 0 ? 0 : v;
  }

  double get completionRatio {
    final s = _stats;
    if (s == null || s.ownedTotal == 0) return 1.0;
    return s.complete / s.ownedTotal;
  }

  int get completionPercent => (completionRatio * 100).round();

  /// Books processed in the current lot ("Tout" tracks the whole run instead).
  int get lotDone {
    if (_lotSize == null) return _progress?.done ?? 0;
    final d = (_progress?.done ?? 0) - _lotStartDone;
    return d < 0 ? 0 : d;
  }

  /// Denominator for the run bar: the lot size, but capped at the books
  /// actually remaining when the lot began — so a lot of 20 over 17 remaining
  /// books shows "/17" and still fills to 100%. "Tout" tracks the whole run.
  int get lotTotal {
    final size = _lotSize;
    if (size == null) return _progress?.total ?? 0;
    final remaining = (_progress?.total ?? 0) - _lotStartDone;
    if (remaining <= 0) return size;
    return remaining < size ? remaining : size;
  }

  /// Load everything for the completeness screen and resume polling if a run
  /// is still live.
  Future<void> loadAll() async {
    await Future.wait([
      loadStats(),
      refreshProgress(),
      loadRecent(),
      loadIncomplete(),
    ]);
    if (isRunning) _startPolling();
  }

  Future<void> loadIncomplete() async {
    try {
      _incomplete = await _ffi.metadataFillIncomplete();
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadIncomplete error: $e');
    }
  }

  /// Reload the data affected by a manual edit (the completeness drops as books
  /// are filled by hand).
  Future<void> refreshAfterManualEdit() async {
    await Future.wait([loadStats(), loadIncomplete()]);
  }

  /// Load the completeness stat. On a cold start the FFI bridge can briefly be
  /// unready ("flutter_rust_bridge has not been initialized"); retry a few times
  /// so the card self-heals once the backend is up, without a manual refresh.
  Future<void> loadStats({int retriesLeft = 4}) async {
    _loadingStats = true;
    _error = null;
    _safeNotify();
    try {
      _stats = await _ffi.metadataFillStats();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('MetadataFillProvider.loadStats error: $e');
      if (retriesLeft > 0) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) loadStats(retriesLeft: retriesLeft - 1);
        });
      }
    } finally {
      _loadingStats = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshProgress() async {
    try {
      _progress = await _ffi.metadataFillProgress();
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.refreshProgress error: $e');
    }
  }

  Future<void> loadRecent() async {
    try {
      _recent = await _ffi.metadataFillRecent(limit: 50);
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadRecent error: $e');
    }
  }


  /// Start (or resume) a bulk run, forwarding reading languages for summary
  /// coherence, then begin polling progress. `lotLimit` bounds this lot (the
  /// "small batches" nudge); null processes the whole backlog.
  Future<void> start(List<String> languages, {int? lotLimit}) async {
    // Lot baseline: a resume continues the same run's cumulative `done`, so the
    // lot starts from there; a fresh run starts the lot from zero.
    _lotStartDone = isResumable ? (_progress?.done ?? 0) : 0;
    _lotSize = lotLimit;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      await _ffi.metadataFillStart(languages: languages, lotLimit: lotLimit);
      await refreshProgress();
      _startPolling();
    } catch (e) {
      _error = e.toString();
      debugPrint('MetadataFillProvider.start error: $e');
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    try {
      await _ffi.metadataFillCancel();
    } catch (e) {
      debugPrint('MetadataFillProvider.cancel error: $e');
    }
    await refreshProgress();
    if (!isRunning) {
      _stopPolling();
      await _onRunFinished();
    }
  }

  /// Undo all fields the fill added to one book (the per-book undo button).
  /// Returns how many fields were actually reverted (fields the user re-edited
  /// are left intact and not counted).
  Future<int> undoBook(String batchId, String bookId) async {
    int reverted = 0;
    try {
      reverted = await _ffi.metadataFillUndoBook(batchId, bookId);
    } catch (e) {
      debugPrint('MetadataFillProvider.undoBook error: $e');
    }
    await Future.wait([loadRecent(), loadStats(), loadIncomplete()]);
    return reverted;
  }

  /// Undo a single filled field. Returns the outcome:
  /// `reverted` | `superseded` | `not_found`.
  Future<String> undoField(int journalId) async {
    String outcome = 'not_found';
    try {
      outcome = await _ffi.metadataFillUndoField(journalId);
    } catch (e) {
      debugPrint('MetadataFillProvider.undoField error: $e');
    }
    await Future.wait([loadRecent(), loadStats(), loadIncomplete()]);
    return outcome;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await refreshProgress();
      if (isRunning) {
        // Keep the completeness teaser climbing live as books are filled.
        await loadStats();
      } else {
        _stopPolling();
        await _onRunFinished();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _onRunFinished() async {
    await Future.wait([
      loadStats(),
      loadRecent(),
      loadIncomplete(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
