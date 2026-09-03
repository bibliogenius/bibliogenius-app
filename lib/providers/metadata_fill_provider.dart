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

  /// Active filter on the "to complete" side: a gap-fill field name,
  /// [noIsbnFilter], or null for the whole backlog. It drives three things at
  /// once, which is why it lives here rather than in the screen: the list the
  /// backend returns, the numbers the teaser and the start button announce, and
  /// the scope a fresh run is started with.
  String? _filter;

  /// Coverless books the sources have already answered empty about, loaded
  /// only while the cover filter is on (null = not loaded / not applicable).
  int? _coversSourcesHaveNot;

  /// Exact backlog for [scopeField], from the backend (null while loading).
  /// Not derived from [incomplete]: that list is capped, so counting it would
  /// under-announce a large scoped run.
  int? _scopedProcessable;

  /// Largest same-day group of owned books with no ISBN (null = not loaded, or
  /// the library has none). One of the two signals behind the "reimport to
  /// complete" banner (ADR-071).
  frb.FrbNoIsbnCluster? _noIsbnCluster;

  frb.FrbCompletenessStats? get stats => _stats;
  frb.FrbNoIsbnCluster? get noIsbnCluster => _noIsbnCluster;
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

  /// Owned books still missing each gap-fill field, exact over the whole
  /// library (the overview list is capped, so it cannot answer this).
  Map<String, int> get fieldGaps => {
    for (final g in _stats?.gaps ?? const []) g.field: g.missing.toInt(),
  };

  /// Owned books still missing [field].
  int fieldGap(String field) => fieldGaps[field] ?? 0;

  /// Share of owned books that already have [field], for the teaser under a
  /// field filter.
  double fieldCompletionRatio(String field) {
    final total = _stats?.ownedTotal.toInt() ?? 0;
    if (total == 0) return 1.0;
    return (total - fieldGap(field)) / total;
  }

  int fieldCompletionPercent(String field) =>
      (fieldCompletionRatio(field) * 100).round();

  /// Number of owned books still missing at least one field, with an ISBN
  /// (the processable backlog).
  int get processableCount {
    final s = _stats;
    if (s == null) return 0;
    final v = s.incomplete - s.noIsbn;
    return v < 0 ? 0 : v;
  }

  /// Sentinel filter for "books with no ISBN". Not a gap-fill field: those
  /// books are precisely the ones an automatic fill can never identify, so it
  /// filters the list but never scopes a run.
  static const String noIsbnFilter = '__no_isbn';

  /// Active filter (field name, [noIsbnFilter], or null).
  String? get filter => _filter;

  /// True while the list is narrowed to the books no fill can process.
  bool get isNoIsbnFilter => _filter == noIsbnFilter;

  /// Field the next run would be scoped to (null = the whole backlog).
  String? get scopeField => isNoIsbnFilter ? null : _filter;

  /// The gap-fill field covers are filed under.
  static const String coverField = 'cover_url';

  /// Among the coverless books, how many the active sources have already been
  /// asked about and answered empty. Null until the cover filter loads it.
  int? get coversSourcesHaveNot => _coversSourcesHaveNot;

  /// Field the current/last run was actually scoped to, as recorded when it
  /// started. Drives the "scope" line on the running / resume strips: a resume
  /// keeps the run's own scope, whatever the filter now says.
  String? get runScopeField => _progress?.missingField;

  /// Books the next run would process under the active scope: the exact backlog
  /// when unscoped, the backend's scoped count otherwise (null while it loads).
  int? get scopedProcessableCount =>
      scopeField == null ? processableCount : _scopedProcessable;

  /// Apply a filter: reloads the list from the backend so the (capped) slice is
  /// drawn from the filtered set, and re-reads the backlog the start button
  /// announces. Passing null clears it.
  Future<void> setFilter(String? filter) async {
    if (filter == _filter) return;
    _filter = filter;
    _scopedProcessable = null;
    notifyListeners();
    await Future.wait([
      loadIncomplete(),
      _loadScopedProcessable(),
      _loadCoversSourcesHaveNot(),
    ]);
  }

  /// Refresh the scoped backlog. A late answer for a scope the user has since
  /// changed is dropped rather than shown against the wrong filter.
  Future<void> _loadScopedProcessable() async {
    final field = scopeField;
    if (field == null) return;
    try {
      final count = await _ffi.metadataFillProcessable(missingField: field);
      if (_disposed || scopeField != field) return;
      _scopedProcessable = count;
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadScopedProcessable error: $e');
    }
  }

  /// Load the "the sources have none" count, but only while the cover filter
  /// is on: it answers a question nobody is asking anywhere else, and it is one
  /// more query on a table join.
  Future<void> _loadCoversSourcesHaveNot() async {
    if (_filter != coverField) {
      _coversSourcesHaveNot = null;
      return;
    }
    try {
      final count = await _ffi.metadataFillCoversSourcesHaveNot();
      if (_disposed || _filter != coverField) return;
      _coversSourcesHaveNot = count;
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadCoversSourcesHaveNot error: $e');
    }
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
      _loadScopedProcessable(),
      _loadCoversSourcesHaveNot(),
    ]);
    if (isRunning) _startPolling();
  }

  Future<void> loadIncomplete() async {
    final requested = _filter;
    try {
      final books = await _ffi.metadataFillIncomplete(
        missingField: scopeField,
        noIsbnOnly: isNoIsbnFilter,
      );
      // A filter changed while this was in flight: its own load is already on
      // its way, and showing this answer would flash the wrong list.
      if (_disposed || _filter != requested) return;
      _incomplete = books;
      notifyListeners();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadIncomplete error: $e');
    }
  }

  /// Reload the data affected by a manual edit (the completeness drops as books
  /// are filled by hand).
  Future<void> refreshAfterManualEdit() async {
    await Future.wait([
      loadStats(),
      loadIncomplete(),
      _loadScopedProcessable(),
    ]);
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
    await _clearFilterIfEmptied();
  }

  // ── Reimport-to-complete signals (ADR-071) ──────────────────────────────

  /// A library must hold at least this many owned books before the banner can
  /// speak: below it, a shelf without ISBNs is a handful of hand-typed books.
  static const int importBannerMinLibrary = 50;

  /// And that many of them, added on a single day, before the shape counts as
  /// a bulk import rather than a habit.
  static const int importBannerMinCluster = 50;

  /// Share of the library that must lack an ISBN.
  static const double importBannerMinRatio = 0.8;

  /// Whether the library looks like an import that lost its ISBN column.
  ///
  /// Two independent signals, both required (ADR-071 D9): most of the library
  /// has no ISBN, AND a large group of those books was added on the same day.
  /// The ratio alone cannot tell a botched import from a shelf typed in by
  /// hand, and accusing the wrong person is worse than staying quiet. Both can
  /// only understate the case, since `noIsbn` counts incomplete books only.
  bool get suggestsFailedImport {
    final stats = _stats;
    final cluster = _noIsbnCluster;
    if (stats == null || cluster == null) return false;
    final owned = stats.ownedTotal.toInt();
    if (owned < importBannerMinLibrary) return false;
    if (cluster.count.toInt() < importBannerMinCluster) return false;
    return stats.noIsbn.toInt() >= owned * importBannerMinRatio;
  }

  /// Load what [suggestsFailedImport] reads: two local queries, no network.
  /// Failures leave the banner silent.
  ///
  /// **Both** are re-read on every call, never only the missing one. This runs
  /// at startup and again after an import, and at startup the library it
  /// measured may have been empty: keeping a stale count would leave the banner
  /// blind at the one moment it exists for, the minutes after an import that
  /// lost its ISBNs.
  ///
  /// No retry: at startup the FFI bridge may not be up yet, and a retry timer
  /// that outlives the caller is a hang in tests and a wakeup on battery. The
  /// completeness screen and the dashboard load the same stat with their own
  /// retries, and the banner is rebuilt when they land.
  Future<void> loadImportSignals() async {
    await loadStats(retriesLeft: 0);
    try {
      _noIsbnCluster = await _ffi.importNoIsbnCluster();
      _safeNotify();
    } catch (e) {
      debugPrint('MetadataFillProvider.loadImportSignals error: $e');
    }
  }

  /// Drop a filter whose slice has emptied (its books were completed, or the
  /// last one without an ISBN got one). Its pill is gone from the bar, so the
  /// user would be left on an empty list with no way to clear it.
  Future<void> _clearFilterIfEmptied() async {
    final active = _filter;
    final stats = _stats;
    if (active == null || stats == null) return;
    final remaining = isNoIsbnFilter ? stats.noIsbn.toInt() : fieldGap(active);
    if (remaining == 0) await setFilter(null);
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
  ///
  /// A fresh run takes the active scope ([setScope]); a resume keeps the scope
  /// stored on the run it continues, since its cursor was built from that
  /// work-list.
  Future<void> start(List<String> languages, {int? lotLimit}) async {
    // Lot baseline: a resume continues the same run's cumulative `done`, so the
    // lot starts from there; a fresh run starts the lot from zero.
    _lotStartDone = isResumable ? (_progress?.done ?? 0) : 0;
    _lotSize = lotLimit;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      await _ffi.metadataFillStart(
        languages: languages,
        lotLimit: lotLimit,
        missingField: scopeField,
      );
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
  /// The batch every entry of the newest completion belongs to, with how many
  /// books it touched, or null when nothing is undoable.
  ///
  /// The recently-completed list is grouped by book and ordered newest first,
  /// so the first entry names the last campaign that ran. A whole campaign has
  /// to stay reversible from a durable screen: the reimport's own summary sheet
  /// offers it, but that sheet closes, and undoing five hundred books one by
  /// one is not an option.
  ({String batchId, int books})? get lastBatch {
    for (final book in _recent) {
      if (book.fields.isNotEmpty) {
        final id = book.fields.first.batchId;
        final books = _recent
            .where((b) => b.fields.any((f) => f.batchId == id))
            .length;
        return (batchId: id, books: books);
      }
    }
    return null;
  }

  /// Revert every field one campaign added. Returns the number reverted.
  Future<int> undoRun(String batchId) async {
    int reverted = 0;
    try {
      reverted = await _ffi.metadataFillUndoRun(batchId);
    } catch (e) {
      debugPrint('MetadataFillProvider.undoRun error: $e');
    }
    // No `loadStats()` here: `loadImportSignals` reloads it, and the banner
    // that offers the repair needs it fresh anyway. A campaign undone is a
    // library back in the state that made the offer relevant.
    await Future.wait([loadRecent(), loadIncomplete()]);
    await loadImportSignals();
    return reverted;
  }

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
      _loadScopedProcessable(),
      _loadCoversSourcesHaveNot(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
