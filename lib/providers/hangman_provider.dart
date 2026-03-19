import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hangman_game.dart';
import '../services/ffi_service.dart';

/// Phases of the hangman game lifecycle.
enum HangmanPhase { setup, playing, complete }

/// Visual mode for the hangman animation.
enum HangmanVisualMode { classic, books }

/// Manages the state of a hangman game session.
///
/// Uses FFI direct calls to the Rust backend (no HTTP detour).
/// Handles letter guessing, hint usage, timing, and scoring.
class HangmanProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  // --- Setup state ---
  List<String> _availableDifficulties = [];
  String? _selectedDifficulty;
  bool _isLoading = false;
  String? _error;

  // --- Visual mode (persisted) ---
  HangmanVisualMode _visualMode = HangmanVisualMode.classic;

  // --- Game state ---
  HangmanPhase _phase = HangmanPhase.setup;
  String _fullTitle = '';
  String _author = '';
  String? _coverUrl;
  List<HangmanChar> _display = [];
  int _bookId = 0;
  Set<String> _guessedChars = {};
  int _errors = 0;
  int _maxErrors = 6;
  int _hintsUsed = 0;
  int _hintsAvailable = 0;
  bool _authorRevealed = false;
  bool _coverRevealed = false;
  bool _won = false;

  // --- Timer ---
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;
  double _elapsedSeconds = 0;

  // --- Score ---
  HangmanGameScore? _lastScore;
  List<HangmanGameScore> _topScores = [];
  List<HangmanLeaderboardEntry> _networkScores = [];
  bool _isSyncingNetwork = false;

  // --- Rank info ---
  int? _personalRank;
  bool _isNewPersonalBest = false;

  // --- Getters ---
  List<String> get availableDifficulties => _availableDifficulties;
  String? get selectedDifficulty => _selectedDifficulty;
  bool get isLoading => _isLoading;
  String? get error => _error;
  HangmanVisualMode get visualMode => _visualMode;
  HangmanPhase get phase => _phase;
  String get fullTitle => _fullTitle;
  String get author => _author;
  String? get coverUrl => _coverUrl;
  List<HangmanChar> get display => _display;
  Set<String> get guessedChars => _guessedChars;
  int get errors => _errors;
  int get maxErrors => _maxErrors;
  int get hintsUsed => _hintsUsed;
  int get hintsAvailable => _hintsAvailable;
  bool get authorRevealed => _authorRevealed;
  bool get coverRevealed => _coverRevealed;
  bool get won => _won;
  double get elapsedSeconds => _elapsedSeconds;
  HangmanGameScore? get lastScore => _lastScore;
  List<HangmanGameScore> get topScores => _topScores;
  List<HangmanLeaderboardEntry> get networkScores => _networkScores;
  bool get isSyncingNetwork => _isSyncingNetwork;
  int? get personalRank => _personalRank;
  bool get isNewPersonalBest => _isNewPersonalBest;

  /// Formatted elapsed time as mm:ss
  String get formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = (_elapsedSeconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Whether the cover hint is available (book has a cover and hint not yet used)
  bool get coverHintAvailable =>
      _coverUrl != null && !_coverRevealed && _hintsUsed < _hintsAvailable;

  /// Whether the author hint is available
  bool get authorHintAvailable =>
      !_authorRevealed && _hintsUsed < _hintsAvailable;

  // --- Setup ---

  /// Load available difficulties and visual mode preference.
  Future<void> loadDifficulties() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _availableDifficulties = await _ffi.getHangmanDifficulties();
      // Load persisted visual mode
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('hangmanVisualMode') ?? 'classic';
      _visualMode = mode == 'books'
          ? HangmanVisualMode.books
          : HangmanVisualMode.classic;
    } catch (e) {
      _error = e.toString();
      debugPrint('HangmanProvider: loadDifficulties error: $e');
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

  /// Toggle visual mode and persist.
  Future<void> setVisualMode(HangmanVisualMode mode) async {
    _visualMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'hangmanVisualMode',
      mode == HangmanVisualMode.books ? 'books' : 'classic',
    );
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
      final setup = await _ffi.setupHangman(_selectedDifficulty!);
      _bookId = setup.bookId;
      _fullTitle = setup.title;
      _display = setup.display
          .map((c) => HangmanChar(
                character: c.character,
                baseChar: c.baseChar,
                revealed: c.revealed,
                isGuessable: c.isGuessable,
              ))
          .toList();
      _author = setup.author;
      _coverUrl = setup.coverUrl;
      _maxErrors = setup.maxErrors;
      _hintsAvailable = setup.hintsAvailable;
      _hintsUsed = 0;
      _errors = 0;
      _guessedChars = {};
      _authorRevealed = false;
      _coverRevealed = false;
      _won = false;
      _lastScore = null;
      _phase = HangmanPhase.playing;

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
      debugPrint('HangmanProvider: startGame error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Guess a character (letter or digit).
  ///
  /// Normalizes to lowercase, checks all display chars,
  /// reveals matches or increments errors.
  void guessChar(String char) {
    if (_phase != HangmanPhase.playing) return;

    final normalized = char.toLowerCase();
    if (_guessedChars.contains(normalized)) return;

    _guessedChars.add(normalized);

    bool found = false;
    for (final dc in _display) {
      if (dc.isGuessable && !dc.revealed && dc.baseChar == normalized) {
        dc.revealed = true;
        found = true;
      }
    }

    if (!found) {
      _errors++;
    }

    // Check win/lose
    if (_display.every((c) => c.revealed)) {
      _won = true;
      _finishGame();
    } else if (_errors >= _maxErrors) {
      _won = false;
      _finishGame();
    } else {
      notifyListeners();
    }
  }

  /// Use a hint (author or cover).
  void useHint() {
    if (_phase != HangmanPhase.playing) return;
    if (_hintsUsed >= _hintsAvailable) return;

    if (!_authorRevealed) {
      _authorRevealed = true;
      _hintsUsed++;
    } else if (_coverUrl != null && !_coverRevealed) {
      _coverRevealed = true;
      _hintsUsed++;
    }
    notifyListeners();
  }

  /// Game ended -- stop timer and submit score via FFI.
  Future<void> _finishGame() async {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
    _phase = HangmanPhase.complete;
    notifyListeners();

    try {
      final frbScore = await _ffi.finishHangman(
        bookId: _bookId,
        difficulty: _selectedDifficulty!,
        elapsedSeconds: _elapsedSeconds,
        errors: _errors,
        hintsUsed: _hintsUsed,
        won: _won,
      );
      _lastScore = HangmanGameScore(
        id: frbScore.id,
        difficulty: frbScore.difficulty,
        elapsedSeconds: frbScore.elapsedSeconds,
        errors: frbScore.errors,
        hintsUsed: frbScore.hintsUsed,
        won: frbScore.won,
        normalizedScore: frbScore.normalizedScore,
        playedAt: frbScore.playedAt,
        newAchievements: frbScore.newAchievements,
      );
      notifyListeners();

      await loadTopScores();
      _computeRank();
      notifyListeners();
    } catch (e) {
      debugPrint('HangmanProvider: finishGame error: $e');
    }
  }

  /// Compute rank of the last score among top scores.
  void _computeRank() {
    if (_lastScore == null || _topScores.isEmpty) {
      _personalRank = null;
      _isNewPersonalBest = false;
      return;
    }

    final scoreId = _lastScore!.id;
    if (scoreId != null) {
      final idx = _topScores.indexWhere((s) => s.id == scoreId);
      if (idx >= 0) {
        _personalRank = idx + 1;
        _isNewPersonalBest = _personalRank == 1;
        return;
      }
    }

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
      final frbScores = await _ffi.getHangmanTopScores();
      _topScores = frbScores
          .map((s) => HangmanGameScore(
                id: s.id,
                difficulty: s.difficulty,
                elapsedSeconds: s.elapsedSeconds,
                errors: s.errors,
                hintsUsed: s.hintsUsed,
                won: s.won,
                normalizedScore: s.normalizedScore,
                playedAt: s.playedAt,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('HangmanProvider: loadTopScores error: $e');
    }
  }

  /// Load network leaderboard via FFI with peer sync.
  Future<void> loadNetworkLeaderboard() async {
    _isSyncingNetwork = true;
    notifyListeners();

    try {
      final frbEntries = await _ffi.refreshHangmanLeaderboard();
      _networkScores = frbEntries
          .map((e) => HangmanLeaderboardEntry(
                peerId: e.peerId,
                libraryName: e.libraryName,
                bestScore: e.bestScore,
                difficulty: e.difficulty,
                playedAt: e.playedAt,
                isSelf: e.isSelf,
              ))
          .toList();
    } catch (e) {
      debugPrint('HangmanProvider: loadNetworkLeaderboard error: $e');
    } finally {
      _isSyncingNetwork = false;
      notifyListeners();
    }
  }

  /// Reset to setup phase for a new game.
  void resetToSetup() {
    _stopwatch.stop();
    _stopwatch.reset();
    _displayTimer?.cancel();
    _phase = HangmanPhase.setup;
    _display = [];
    _guessedChars = {};
    _errors = 0;
    _hintsUsed = 0;
    _authorRevealed = false;
    _coverRevealed = false;
    _won = false;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    _personalRank = null;
    _isNewPersonalBest = false;
    notifyListeners();
  }

  /// Play again with the same difficulty.
  Future<void> playAgain() async {
    _phase = HangmanPhase.setup;
    _display = [];
    _guessedChars = {};
    _errors = 0;
    _hintsUsed = 0;
    _authorRevealed = false;
    _coverRevealed = false;
    _won = false;
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
    super.dispose();
  }
}
