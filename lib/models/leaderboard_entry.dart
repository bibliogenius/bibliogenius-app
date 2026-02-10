class LeaderboardEntry {
  final String libraryName;
  final int level;
  final int current;
  final bool isSelf;
  final int? peerId;

  const LeaderboardEntry({
    required this.libraryName,
    required this.level,
    required this.current,
    required this.isSelf,
    this.peerId,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      libraryName: json['library_name'] ?? '',
      level: json['level'] ?? 0,
      current: (json['current'] is int)
          ? json['current']
          : (json['current'] as num).toInt(),
      isSelf: json['is_self'] ?? false,
      peerId: json['peer_id'],
    );
  }
}
