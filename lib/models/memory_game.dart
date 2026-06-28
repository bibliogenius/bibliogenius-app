/// Memory Game models matching the Rust backend API responses.
///
/// Three main types:
/// - [MemoryCard] — a card in the game (book cover)
/// - [MemoryGameScore] — a saved score after finishing a game
/// - [MemoryLeaderboardEntry] — a peer's best score for the leaderboard
library;

/// A card in the memory game, representing a book cover.
class MemoryCard {
  final String bookId;
  final String title;
  final String coverUrl;

  /// Runtime state (not from backend)
  bool isFlipped;
  bool isMatched;

  MemoryCard({
    required this.bookId,
    required this.title,
    required this.coverUrl,
    this.isFlipped = false,
    this.isMatched = false,
  });

  factory MemoryCard.fromJson(Map<String, dynamic> json) {
    return MemoryCard(
      bookId: json['book_id'].toString(),
      title: json['title'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
    );
  }
}

/// A saved memory game score.
class MemoryGameScore {
  final int? id;
  final String difficulty;
  final int pairsCount;
  final double elapsedSeconds;
  final int errors;
  final double normalizedScore;
  final String playedAt;
  final List<String> newAchievements;

  const MemoryGameScore({
    this.id,
    required this.difficulty,
    required this.pairsCount,
    required this.elapsedSeconds,
    required this.errors,
    required this.normalizedScore,
    required this.playedAt,
    this.newAchievements = const [],
  });

  factory MemoryGameScore.fromJson(Map<String, dynamic> json) {
    return MemoryGameScore(
      id: json['id'] as int?,
      difficulty: json['difficulty'] as String? ?? 'easy',
      pairsCount: (json['pairs_count'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
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

/// A leaderboard entry for the memory game (peer scores + local user).
class MemoryLeaderboardEntry {
  final int peerId;
  final String libraryName;
  final double bestScore;
  final String difficulty;
  final String playedAt;
  final bool isSelf;

  const MemoryLeaderboardEntry({
    required this.peerId,
    required this.libraryName,
    required this.bestScore,
    required this.difficulty,
    required this.playedAt,
    this.isSelf = false,
  });

  factory MemoryLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return MemoryLeaderboardEntry(
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
