/// Sliding Puzzle models matching the Rust backend API responses.
///
/// Three main types:
/// - [PuzzleBoard] - a generated board with tiles and book cover info
/// - [PuzzleScore] - a saved score after finishing a game
/// - [PuzzleLeaderboardEntry] - a peer's best score for the leaderboard
library;

/// A generated sliding puzzle board ready to play.
class PuzzleBoard {
  final int bookId;
  final String title;
  final String coverUrl;
  final int gridSize;
  final List<int> tiles;
  final int emptyIndex;
  final int parMoves;

  const PuzzleBoard({
    required this.bookId,
    required this.title,
    required this.coverUrl,
    required this.gridSize,
    required this.tiles,
    required this.emptyIndex,
    required this.parMoves,
  });

  factory PuzzleBoard.fromJson(Map<String, dynamic> json) {
    return PuzzleBoard(
      bookId: json['book_id'] as int,
      title: json['title'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      gridSize: (json['grid_size'] as num?)?.toInt() ?? 3,
      tiles:
          (json['tiles'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      emptyIndex: (json['empty_index'] as num?)?.toInt() ?? 0,
      parMoves: (json['par_moves'] as num?)?.toInt() ?? 120,
    );
  }
}

/// A saved sliding puzzle score.
class PuzzleScore {
  final int? id;
  final String difficulty;
  final int gridSize;
  final double elapsedSeconds;
  final int moveCount;
  final int parMoves;
  final double normalizedScore;
  final String playedAt;
  final List<String> newAchievements;

  const PuzzleScore({
    this.id,
    required this.difficulty,
    required this.gridSize,
    required this.elapsedSeconds,
    required this.moveCount,
    required this.parMoves,
    required this.normalizedScore,
    required this.playedAt,
    this.newAchievements = const [],
  });

  factory PuzzleScore.fromJson(Map<String, dynamic> json) {
    return PuzzleScore(
      id: json['id'] as int?,
      difficulty: json['difficulty'] as String? ?? 'easy',
      gridSize: (json['grid_size'] as num?)?.toInt() ?? 3,
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
      moveCount: (json['move_count'] as num?)?.toInt() ?? 0,
      parMoves: (json['par_moves'] as num?)?.toInt() ?? 40,
      normalizedScore: (json['normalized_score'] as num?)?.toDouble() ?? 0.0,
      playedAt: json['played_at'] as String? ?? '',
    );
  }

  /// Format elapsed time as mm:ss
  String get formattedTime {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = (elapsedSeconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format score as integer
  String get formattedScore => normalizedScore.round().toString();
}

/// A leaderboard entry for the sliding puzzle (peer scores + local user).
class PuzzleLeaderboardEntry {
  final int peerId;
  final String libraryName;
  final double bestScore;
  final String difficulty;
  final String playedAt;
  final bool isSelf;

  const PuzzleLeaderboardEntry({
    required this.peerId,
    required this.libraryName,
    required this.bestScore,
    required this.difficulty,
    required this.playedAt,
    this.isSelf = false,
  });

  factory PuzzleLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return PuzzleLeaderboardEntry(
      peerId: json['peer_id'] as int? ?? 0,
      libraryName: json['library_name'] as String? ?? '',
      bestScore: (json['best_score'] as num?)?.toDouble() ?? 0.0,
      difficulty: json['difficulty'] as String? ?? 'easy',
      playedAt: json['played_at'] as String? ?? '',
      isSelf: json['is_self'] as bool? ?? false,
    );
  }

  /// Format score as integer
  String get formattedScore => bestScore.round().toString();
}
