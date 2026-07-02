import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/memory_game.dart';
import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' show subscribeLeaderboardChanges;

/// Phases of the memory game lifecycle.
enum GamePhase { setup, playing, matchCheck, complete }

/// Manages the state of a memory game session.
///
/// Uses FFI direct calls to the Rust backend (no HTTP detour).
/// Handles card flipping logic, match detection, timing,
/// error counting, and scoring.
class MemoryGameProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  // --- Setup state ---
  List<String> _availableDifficulties = [];
  String? _selectedDifficulty;
  bool _isLoading = false;
  String? _error;

  // --- Game state ---
  GamePhase _phase = GamePhase.setup;
  List<MemoryCard> _cards = [];
  int? _firstFlippedIndex;
  int? _secondFlippedIndex;
  int _matchedPairs = 0;
  int _totalPairs = 0;
  int _errors = 0;

  // --- Timer ---
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;
  double _elapsedSeconds = 0;

  // --- Score ---
  MemoryGameScore? _lastScore;
  List<MemoryGameScore> _topScores = [];
  List<MemoryLeaderboardEntry> _networkScores = [];
  bool _isSyncingNetwork = false;
  bool _lastRefreshTimedOut = false;

  // --- Rank info (computed after game finish) ---
  int? _personalRank;
  bool _isNewPersonalBest = false;

  // --- ADR-023: live leaderboard push subscription ---
  StreamSubscription<dynamic>? _leaderboardChangeSub;

  // --- Getters ---
  List<String> get availableDifficulties => _availableDifficulties;
  String? get selectedDifficulty => _selectedDifficulty;
  bool get isLoading => _isLoading;
  String? get error => _error;
  GamePhase get phase => _phase;
  List<MemoryCard> get cards => _cards;
  int get matchedPairs => _matchedPairs;
  int get totalPairs => _totalPairs;
  int get errors => _errors;
  double get elapsedSeconds => _elapsedSeconds;
  MemoryGameScore? get lastScore => _lastScore;
  List<MemoryGameScore> get topScores => _topScores;
  List<MemoryLeaderboardEntry> get networkScores => _networkScores;
  bool get isSyncingNetwork => _isSyncingNetwork;
  bool get lastRefreshTimedOut => _lastRefreshTimedOut;
  bool get isMatchChecking => _phase == GamePhase.matchCheck;
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
      _availableDifficulties = await _ffi.getMemoryDifficulties();
    } catch (e) {
      _error = e.toString();
      debugPrint('MemoryGameProvider: loadDifficulties error: $e');
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

  /// Best (fastest) recorded time for a difficulty among the local top scores,
  /// formatted as m:ss, or null if that tier was never completed. Powers the
  /// "best time" preview shown when a difficulty is expanded on the setup
  /// screen.
  String? bestTimeFor(String difficulty) {
    final times = _topScores
        .where((s) => s.difficulty == difficulty)
        .map((s) => s.elapsedSeconds);
    if (times.isEmpty) return null;
    final best = times.reduce((a, b) => a < b ? a : b);
    final minutes = best ~/ 60;
    final seconds = (best % 60).toInt();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // --- Game lifecycle ---

  /// Start a new game with the selected difficulty.
  Future<void> startGame() async {
    if (_selectedDifficulty == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final frbCards = await _ffi.setupMemoryGame(_selectedDifficulty!);
      _cards = frbCards
          .map(
            (c) => MemoryCard(
              bookId: c.bookId,
              title: c.title,
              coverUrl: c.coverUrl,
            ),
          )
          .toList();
      _totalPairs = _cards.length ~/ 2;
      _matchedPairs = 0;
      _errors = 0;
      _firstFlippedIndex = null;
      _secondFlippedIndex = null;
      _lastScore = null;
      _phase = GamePhase.playing;

      // Start timer
      _stopwatch.reset();
      _stopwatch.start();
      _elapsedSeconds = 0;
      _displayTimer?.cancel();
      _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      debugPrint('MemoryGameProvider: startGame error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flip a card at the given index.
  ///
  /// If it's the first card, just flip it.
  /// If it's the second card, check for a match after a short delay.
  void flipCard(int index) {
    if (_phase != GamePhase.playing) return;
    if (index < 0 || index >= _cards.length) return;

    final card = _cards[index];

    // Ignore already matched or already flipped cards
    if (card.isMatched || card.isFlipped) return;

    card.isFlipped = true;

    if (_firstFlippedIndex == null) {
      // First card of the pair
      _firstFlippedIndex = index;
      notifyListeners();
    } else {
      // Second card of the pair
      _secondFlippedIndex = index;
      _phase = GamePhase.matchCheck;
      notifyListeners();

      // Check match after a short delay (let the player see both cards)
      Future.delayed(const Duration(milliseconds: 800), () {
        _checkMatch();
      });
    }
  }

  /// Check if the two flipped cards match.
  void _checkMatch() {
    if (_firstFlippedIndex == null || _secondFlippedIndex == null) return;

    final first = _cards[_firstFlippedIndex!];
    final second = _cards[_secondFlippedIndex!];

    if (first.bookId == second.bookId) {
      // Match found
      first.isMatched = true;
      second.isMatched = true;
      _matchedPairs++;

      if (_matchedPairs >= _totalPairs) {
        _finishGame();
        return;
      }
    } else {
      // No match — flip back
      first.isFlipped = false;
      second.isFlipped = false;
      _errors++;
    }

    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _phase = GamePhase.playing;
    notifyListeners();
  }

  /// All pairs matched — stop timer and submit score via FFI.
  Future<void> _finishGame() async {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
    _phase = GamePhase.complete;
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    notifyListeners();

    try {
      final frbScore = await _ffi.finishMemoryGame(
        difficulty: _selectedDifficulty!,
        elapsedSeconds: _elapsedSeconds,
        errors: _errors,
        pairsCount: _totalPairs,
      );
      _lastScore = MemoryGameScore(
        id: frbScore.id,
        difficulty: frbScore.difficulty,
        pairsCount: frbScore.pairsCount,
        elapsedSeconds: frbScore.elapsedSeconds,
        errors: frbScore.errors,
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
      debugPrint('MemoryGameProvider: finishGame error: $e');
    }
  }

  /// Compute rank of the last score among top scores.
  void _computeRank() {
    if (_lastScore == null || _topScores.isEmpty) {
      _personalRank = null;
      _isNewPersonalBest = false;
      return;
    }

    // Top scores are sorted by normalized_score DESC — find position
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
      final frbScores = await _ffi.getMemoryTopScores();
      _topScores = frbScores
          .map(
            (s) => MemoryGameScore(
              id: s.id,
              difficulty: s.difficulty,
              pairsCount: s.pairsCount,
              elapsedSeconds: s.elapsedSeconds,
              errors: s.errors,
              normalizedScore: s.normalizedScore,
              playedAt: s.playedAt,
            ),
          )
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('MemoryGameProvider: loadTopScores error: $e');
    }
  }

  /// Subscribe to live leaderboard push events (ADR-023).
  /// Call once when the leaderboard screen is shown. Automatically reloads
  /// network scores when a peer pushes updated stats.
  void subscribeToLeaderboardPush() {
    if (_leaderboardChangeSub != null) return;
    _leaderboardChangeSub = subscribeLeaderboardChanges().listen(
      (_) => _silentReloadNetworkScores(),
      onError: (e) =>
          debugPrint('MemoryGameProvider: leaderboard stream error: $e'),
    );
  }

  bool _backgroundSyncRunning = false;

  /// Reload network scores from cache only (no relay sync).
  /// Called by push notifications (ADR-023) which already updated the cache.
  Future<void> _silentReloadNetworkScores() async {
    await _loadCachedScores();
  }

  /// Read cached leaderboard from local DB (instant, ~3ms).
  Future<void> _loadCachedScores() async {
    try {
      final frbEntries = await _ffi.getMemoryLeaderboard();
      _networkScores = frbEntries
          .map(
            (e) => MemoryLeaderboardEntry(
              peerId: e.peerId,
              libraryName: e.libraryName,
              bestScore: e.bestScore,
              difficulty: e.difficulty,
              playedAt: e.playedAt,
              isSelf: e.isSelf,
            ),
          )
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('MemoryGameProvider: loadCachedScores error: $e');
    }
  }

  /// Load leaderboard: show cached scores instantly, then sync peers in
  /// the background (invisible, no spinner). Called when opening the sheet.
  Future<void> loadNetworkLeaderboard() async {
    await _loadCachedScores();
    _syncPeersInBackground();
  }

  /// Fire-and-forget background peer sync. Updates scores silently when done.
  void _syncPeersInBackground() {
    if (_backgroundSyncRunning || _isSyncingNetwork) return;
    _backgroundSyncRunning = true;
    _ffi
        .refreshMemoryLeaderboard()
        .then((frbEntries) {
          _networkScores = frbEntries
              .map(
                (e) => MemoryLeaderboardEntry(
                  peerId: e.peerId,
                  libraryName: e.libraryName,
                  bestScore: e.bestScore,
                  difficulty: e.difficulty,
                  playedAt: e.playedAt,
                  isSelf: e.isSelf,
                ),
              )
              .toList();
          _backgroundSyncRunning = false;
          notifyListeners();
        })
        .catchError((e) {
          debugPrint('MemoryGameProvider: background sync error: $e');
          _backgroundSyncRunning = false;
        });
  }

  /// Force relay sync with spinner. Called from the manual refresh button.
  ///
  /// Capped at 15s client-side: Rust Phase 2 relay times out per-peer at
  /// 8s and unreachable peers are cached, so a cold refresh rarely exceeds
  /// ~10s. On timeout, reloads from cache and sets [lastRefreshTimedOut].
  Future<void> refreshNetworkLeaderboard() async {
    if (_isSyncingNetwork) return;

    _isSyncingNetwork = true;
    _lastRefreshTimedOut = false;
    notifyListeners();

    final spinnerStart = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      final frbEntries = await _ffi.refreshMemoryLeaderboard().timeout(
        const Duration(seconds: 15),
      );
      _networkScores = frbEntries
          .map(
            (e) => MemoryLeaderboardEntry(
              peerId: e.peerId,
              libraryName: e.libraryName,
              bestScore: e.bestScore,
              difficulty: e.difficulty,
              playedAt: e.playedAt,
              isSelf: e.isSelf,
            ),
          )
          .toList();
    } on TimeoutException {
      _lastRefreshTimedOut = true;
      debugPrint(
        'MemoryGameProvider: refreshNetworkLeaderboard timed out, reloading cache',
      );
      await _loadCachedScores();
    } catch (e) {
      debugPrint('MemoryGameProvider: refreshNetworkLeaderboard error: $e');
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

  /// Delete all local memory game scores and reload leaderboard.
  Future<void> resetScores() async {
    await _ffi.resetMemoryScores();
    _topScores = [];
    _networkScores = [];
    notifyListeners();
    await _loadCachedScores();
  }

  /// Reset to setup phase for a new game.
  void resetToSetup() {
    _stopwatch.stop();
    _stopwatch.reset();
    _displayTimer?.cancel();
    _phase = GamePhase.setup;
    _cards = [];
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _matchedPairs = 0;
    _totalPairs = 0;
    _errors = 0;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    _personalRank = null;
    _isNewPersonalBest = false;
    notifyListeners();
  }

  /// Play again with the same difficulty.
  Future<void> playAgain() async {
    _phase = GamePhase.setup;
    _cards = [];
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _matchedPairs = 0;
    _errors = 0;
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
