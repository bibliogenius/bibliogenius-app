/// Hangman Game models matching the Rust backend API responses.
///
/// Three main types:
/// - [HangmanChar] -- a character in the hangman display
/// - [HangmanGameScore] -- a saved score after finishing a game
/// - [HangmanLeaderboardEntry] -- a peer's best score for the leaderboard
library;

/// A single character in the hangman display.
class HangmanChar {
  final String character;
  final String baseChar;
  bool revealed;
  final bool isGuessable;

  HangmanChar({
    required this.character,
    required this.baseChar,
    required this.revealed,
    required this.isGuessable,
  });
}

/// Game setup data returned from the Rust backend.
class HangmanSetup {
  final String title;
  final List<HangmanChar> display;
  final String author;
  final String? coverUrl;
  final int maxErrors;
  final int hintsAvailable;
  final String difficulty;

  const HangmanSetup({
    required this.title,
    required this.display,
    required this.author,
    this.coverUrl,
    required this.maxErrors,
    required this.hintsAvailable,
    required this.difficulty,
  });
}

/// A saved hangman game score.
class HangmanGameScore {
  final int? id;
  final String difficulty;
  final double elapsedSeconds;
  final int errors;
  final int hintsUsed;
  final bool won;
  final double normalizedScore;
  final String playedAt;
  final List<String> newAchievements;

  const HangmanGameScore({
    this.id,
    required this.difficulty,
    required this.elapsedSeconds,
    required this.errors,
    required this.hintsUsed,
    required this.won,
    required this.normalizedScore,
    required this.playedAt,
    this.newAchievements = const [],
  });

  /// Format elapsed time as mm:ss
  String get formattedTime {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = (elapsedSeconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format score as integer
  String get formattedScore => normalizedScore.round().toString();
}

/// A leaderboard entry for the hangman game (peer scores + local user).
class HangmanLeaderboardEntry {
  final int peerId;
  final String libraryName;
  final double bestScore;
  final String difficulty;
  final String playedAt;
  final bool isSelf;

  const HangmanLeaderboardEntry({
    required this.peerId,
    required this.libraryName,
    required this.bestScore,
    required this.difficulty,
    required this.playedAt,
    this.isSelf = false,
  });

  /// Format score as integer
  String get formattedScore => bestScore.round().toString();
}
