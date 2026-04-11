import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sliding_puzzle.dart';
import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' show subscribeLeaderboardChanges;

/// Phases of the sliding puzzle lifecycle.
enum PuzzlePhase { setup, playing, complete }

/// Manages the state of a sliding puzzle session.
///
/// Uses FFI direct calls to the Rust backend (no HTTP detour).
/// Handles tile movement logic, win detection, timing,
/// move counting, and scoring.
class SlidingPuzzleProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  // --- Setup state ---
  List<String> _availableDifficulties = [];
  String? _selectedDifficulty;
  bool _isLoading = false;
  String? _error;

  // --- Game state ---
  PuzzlePhase _phase = PuzzlePhase.setup;
  PuzzleBoard? _board;
  List<int> _tiles = [];
  int _emptyIndex = 0;
  int _moveCount = 0;
  int _gridSize = 3;
  int _parMoves = 120;

  // --- Timer ---
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;
  double _elapsedSeconds = 0;

  // --- Score ---
  PuzzleScore? _lastScore;
  List<PuzzleScore> _topScores = [];
  List<PuzzleLeaderboardEntry> _networkScores = [];
  bool _isSyncingNetwork = false;

  // --- Rank info ---
  int? _personalRank;
  bool _isNewPersonalBest = false;

  // --- ADR-023: live leaderboard push subscription ---
  StreamSubscription<dynamic>? _leaderboardChangeSub;

  // --- Getters ---
  List<String> get availableDifficulties => _availableDifficulties;
  String? get selectedDifficulty => _selectedDifficulty;
  bool get isLoading => _isLoading;
  String? get error => _error;
  PuzzlePhase get phase => _phase;
  PuzzleBoard? get board => _board;
  List<int> get tiles => _tiles;
  int get emptyIndex => _emptyIndex;
  int get moveCount => _moveCount;
  int get gridSize => _gridSize;
  int get parMoves => _parMoves;
  double get elapsedSeconds => _elapsedSeconds;
  PuzzleScore? get lastScore => _lastScore;
  List<PuzzleScore> get topScores => _topScores;
  List<PuzzleLeaderboardEntry> get networkScores => _networkScores;
  bool get isSyncingNetwork => _isSyncingNetwork;
  int? get personalRank => _personalRank;
  bool get isNewPersonalBest => _isNewPersonalBest;

  /// Formatted elapsed time as mm:ss
  String get formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = (_elapsedSeconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // --- Setup ---

  /// Load available difficulties from the backend via FFI.
  Future<void> loadDifficulties() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _availableDifficulties = await _ffi.getPuzzleDifficulties();
    } catch (e) {
      _error = e.toString();
      debugPrint('SlidingPuzzleProvider: loadDifficulties error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select a difficulty level.
  void selectDifficulty(String difficulty) {
    _selectedDifficulty = difficulty;
    notifyListeners();
  }

  // --- Game lifecycle ---

  /// Start a new game with the selected difficulty.
  Future<void> startGame() async {
    if (_selectedDifficulty == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final frbBoard = await _ffi.setupPuzzle(_selectedDifficulty!);
      _board = PuzzleBoard(
        bookId: frbBoard.bookId,
        title: frbBoard.title,
        coverUrl: frbBoard.coverUrl,
        gridSize: frbBoard.gridSize,
        tiles: frbBoard.tiles.toList(),
        emptyIndex: frbBoard.emptyIndex,
        parMoves: frbBoard.parMoves,
      );
      _tiles = List<int>.from(_board!.tiles);
      _emptyIndex = _board!.emptyIndex;
      _gridSize = _board!.gridSize;
      _parMoves = _board!.parMoves;
      _moveCount = 0;
      _lastScore = null;
      _phase = PuzzlePhase.playing;

      // Start timer
      _stopwatch.reset();
      _stopwatch.start();
      _elapsedSeconds = 0;
      _displayTimer?.cancel();
      _displayTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = e.toString();
      debugPrint('SlidingPuzzleProvider: startGame error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if a tile at [index] is adjacent to the empty space.
  bool isAdjacentToEmpty(int index) {
    final row = index ~/ _gridSize;
    final col = index % _gridSize;
    final emptyRow = _emptyIndex ~/ _gridSize;
    final emptyCol = _emptyIndex % _gridSize;

    return (row == emptyRow && (col - emptyCol).abs() == 1) ||
        (col == emptyCol && (row - emptyRow).abs() == 1);
  }

  /// Move a tile at [index] into the empty space.
  ///
  /// Returns true if the move was valid and executed.
  bool moveTile(int index) {
    if (_phase != PuzzlePhase.playing) return false;
    if (index < 0 || index >= _tiles.length) return false;
    if (!isAdjacentToEmpty(index)) return false;

    // Swap tile with empty space
    _tiles[_emptyIndex] = _tiles[index];
    _tiles[index] = 0;
    _emptyIndex = index;
    _moveCount++;
    notifyListeners();

    // Check win condition
    if (_isSolved()) {
      _finishGame();
    }

    return true;
  }

  /// Check if the puzzle is solved: tiles are [1, 2, ..., N*N-1, 0].
  bool _isSolved() {
    final total = _gridSize * _gridSize;
    for (int i = 0; i < total - 1; i++) {
      if (_tiles[i] != i + 1) return false;
    }
    return _tiles[total - 1] == 0;
  }

  /// Puzzle solved - stop timer and submit score via FFI.
  Future<void> _finishGame() async {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
    _phase = PuzzlePhase.complete;
    notifyListeners();

    try {
      final frbScore = await _ffi.finishPuzzle(
        difficulty: _selectedDifficulty!,
        gridSize: _gridSize,
        elapsedSeconds: _elapsedSeconds,
        moveCount: _moveCount,
        parMoves: _parMoves,
      );
      _lastScore = PuzzleScore(
        id: frbScore.id,
        difficulty: frbScore.difficulty,
        gridSize: frbScore.gridSize,
        elapsedSeconds: frbScore.elapsedSeconds,
        moveCount: frbScore.moveCount,
        parMoves: frbScore.parMoves,
        normalizedScore: frbScore.normalizedScore,
        playedAt: frbScore.playedAt,
        newAchievements: frbScore.newAchievements,
      );
      notifyListeners();

      // Load top scores to compute rank
      await loadTopScores();
      _computeRank();
      notifyListeners();
    } catch (e) {
      debugPrint('SlidingPuzzleProvider: finishGame error: $e');
    }
  }

  /// Compute rank of the last score among top scores.
  void _computeRank() {
    if (_lastScore == null || _topScores.isEmpty) {
      _personalRank = null;
      _isNewPersonalBest = false;
      return;
    }

    // Top scores are sorted by normalized_score DESC - find position
    final scoreId = _lastScore!.id;
    if (scoreId != null) {
      final idx = _topScores.indexWhere((s) => s.id == scoreId);
      if (idx >= 0) {
        _personalRank = idx + 1; // 1-based
        _isNewPersonalBest = _personalRank == 1;
        return;
      }
    }

    // Fallback: compare by score value
    final newScore = _lastScore!.normalizedScore;
    int rank = 1;
    for (final s in _topScores) {
      if (s.normalizedScore > newScore) {
        rank++;
      } else {
        break;
      }
    }
    _personalRank = rank;
    _isNewPersonalBest = rank == 1;
  }

  /// Load top scores from the backend via FFI.
  Future<void> loadTopScores() async {
    try {
      final frbScores = await _ffi.getPuzzleTopScores();
      _topScores = frbScores
          .map((s) => PuzzleScore(
                id: s.id,
                difficulty: s.difficulty,
                gridSize: s.gridSize,
                elapsedSeconds: s.elapsedSeconds,
                moveCount: s.moveCount,
                parMoves: s.parMoves,
                normalizedScore: s.normalizedScore,
                playedAt: s.playedAt,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('SlidingPuzzleProvider: loadTopScores error: $e');
    }
  }

  /// Subscribe to live leaderboard push events (ADR-023).
  void subscribeToLeaderboardPush() {
    if (_leaderboardChangeSub != null) return;
    _leaderboardChangeSub = subscribeLeaderboardChanges().listen(
      (_) => _silentReloadNetworkScores(),
      onError: (e) =>
          debugPrint('SlidingPuzzleProvider: leaderboard stream error: $e'),
    );
  }

  bool _backgroundSyncRunning = false;

  /// Reload network scores from cache only (no relay sync).
  Future<void> _silentReloadNetworkScores() async {
    await _loadCachedScores();
  }

  Future<void> _loadCachedScores() async {
    try {
      final frbEntries = await _ffi.getPuzzleLeaderboard();
      _networkScores = frbEntries
          .map((e) => PuzzleLeaderboardEntry(
                peerId: e.peerId,
                libraryName: e.libraryName,
                bestScore: e.bestScore,
                difficulty: e.difficulty,
                playedAt: e.playedAt,
                isSelf: e.isSelf,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('SlidingPuzzleProvider: loadCachedScores error: $e');
    }
  }

  /// Load leaderboard: cached scores instantly, then sync peers invisibly.
  Future<void> loadNetworkLeaderboard() async {
    await _loadCachedScores();
    _syncPeersInBackground();
  }

  void _syncPeersInBackground() {
    if (_backgroundSyncRunning || _isSyncingNetwork) return;
    _backgroundSyncRunning = true;
    _ffi.refreshPuzzleLeaderboard().then((frbEntries) {
      _networkScores = frbEntries
          .map((e) => PuzzleLeaderboardEntry(
                peerId: e.peerId,
                libraryName: e.libraryName,
                bestScore: e.bestScore,
                difficulty: e.difficulty,
                playedAt: e.playedAt,
                isSelf: e.isSelf,
              ))
          .toList();
      _backgroundSyncRunning = false;
      notifyListeners();
    }).catchError((e) {
      debugPrint('SlidingPuzzleProvider: background sync error: $e');
      _backgroundSyncRunning = false;
    });
  }

  /// Force relay sync with spinner. Called from the manual refresh button.
  Future<void> refreshNetworkLeaderboard() async {
    if (_isSyncingNetwork) return;
    _isSyncingNetwork = true;
    notifyListeners();

    final spinnerStart = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      final frbEntries = await _ffi.refreshPuzzleLeaderboard();
      _networkScores = frbEntries
          .map((e) => PuzzleLeaderboardEntry(
                peerId: e.peerId,
                libraryName: e.libraryName,
                bestScore: e.bestScore,
                difficulty: e.difficulty,
                playedAt: e.playedAt,
                isSelf: e.isSelf,
              ))
          .toList();
    } catch (e) {
      debugPrint('SlidingPuzzleProvider: refreshNetworkLeaderboard error: $e');
    } finally {
      final elapsed = DateTime.now().difference(spinnerStart);
      const minDuration = Duration(milliseconds: 800);
      if (elapsed < minDuration) {
        await Future<void>.delayed(minDuration - elapsed);
      }
      _isSyncingNetwork = false;
      notifyListeners();
    }
  }

  /// Reset to setup phase for a new game.
  /// Delete all local sliding puzzle scores and reload leaderboard.
  Future<void> resetScores() async {
    await _ffi.resetPuzzleScores();
    _topScores = [];
    _networkScores = [];
    notifyListeners();
    await _loadCachedScores();
  }

  void resetToSetup() {
    _stopwatch.stop();
    _stopwatch.reset();
    _displayTimer?.cancel();
    _phase = PuzzlePhase.setup;
    _board = null;
    _tiles = [];
    _emptyIndex = 0;
    _moveCount = 0;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    _personalRank = null;
    _isNewPersonalBest = false;
    notifyListeners();
  }

  /// Play again with the same difficulty.
  Future<void> playAgain() async {
    _phase = PuzzlePhase.setup;
    _board = null;
    _tiles = [];
    _emptyIndex = 0;
    _moveCount = 0;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    _personalRank = null;
    _isNewPersonalBest = false;
    notifyListeners();
    await startGame();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _leaderboardChangeSub?.cancel();
    super.dispose();
  }
}
