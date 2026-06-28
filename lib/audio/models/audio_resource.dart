/// Represents an audiobook resource found from external sources.
///
/// This model stores metadata about audiobooks discovered from:
/// - LibriVox (primary source, global catalog)
/// - Litteratureaudio.com (French audiobooks)
/// - Internet Archive (fallback)
class AudioResource {
  final int? id;
  final String bookId;
  final AudioSource source;
  final String sourceId;
  final String title;
  final String? language;
  final int? durationSeconds;
  final String? streamUrl;
  final String? rssUrl;
  final String? narrator;
  final List<AudioChapter>? chapters;
  final DateTime createdAt;
  final DateTime updatedAt;

  AudioResource({
    this.id,
    required this.bookId,
    required this.source,
    required this.sourceId,
    required this.title,
    this.language,
    this.durationSeconds,
    this.streamUrl,
    this.rssUrl,
    this.narrator,
    this.chapters,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Create from JSON (database or API response)
  factory AudioResource.fromJson(Map<String, dynamic> json) {
    return AudioResource(
      id: json['id'] as int?,
      bookId: json['book_id'].toString(),
      source: AudioSource.fromString(json['source'] as String),
      sourceId: json['source_id'] as String,
      title: json['title'] as String,
      language: json['language'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
      streamUrl: json['stream_url'] as String?,
      rssUrl: json['rss_url'] as String?,
      narrator: json['narrator'] as String?,
      chapters: json['chapters'] != null
          ? (json['chapters'] as List)
                .map((c) => AudioChapter.fromJson(c as Map<String, dynamic>))
                .toList()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'source': source.name,
      'source_id': sourceId,
      'title': title,
      'language': language,
      'duration_seconds': durationSeconds,
      'stream_url': streamUrl,
      'rss_url': rssUrl,
      'narrator': narrator,
      'chapters': chapters?.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get the best available stream URL
  String? get playableUrl => streamUrl ?? chapters?.firstOrNull?.url;

  /// Format duration as HH:MM:SS
  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final hours = durationSeconds! ~/ 3600;
    final minutes = (durationSeconds! % 3600) ~/ 60;
    final seconds = durationSeconds! % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Create a copy with updated fields
  AudioResource copyWith({
    int? id,
    String? bookId,
    AudioSource? source,
    String? sourceId,
    String? title,
    String? language,
    int? durationSeconds,
    String? streamUrl,
    String? rssUrl,
    String? narrator,
    List<AudioChapter>? chapters,
  }) {
    return AudioResource(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      language: language ?? this.language,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      streamUrl: streamUrl ?? this.streamUrl,
      rssUrl: rssUrl ?? this.rssUrl,
      narrator: narrator ?? this.narrator,
      chapters: chapters ?? this.chapters,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Audiobook source identifier
enum AudioSource {
  librivox,
  litteratureaudio,
  archive;

  String get displayName {
    switch (this) {
      case AudioSource.librivox:
        return 'LibriVox';
      case AudioSource.litteratureaudio:
        return 'Littérature Audio';
      case AudioSource.archive:
        return 'Internet Archive';
    }
  }

  String get websiteUrl {
    switch (this) {
      case AudioSource.librivox:
        return 'https://librivox.org';
      case AudioSource.litteratureaudio:
        return 'https://www.litteratureaudio.com';
      case AudioSource.archive:
        return 'https://archive.org';
    }
  }

  static AudioSource fromString(String value) {
    return AudioSource.values.firstWhere(
      (s) => s.name == value.toLowerCase(),
      orElse: () => AudioSource.librivox,
    );
  }
}

/// Represents a chapter/section of an audiobook
class AudioChapter {
  final String id;
  final String title;
  final String url;
  final int? durationSeconds;
  final int index;

  AudioChapter({
    required this.id,
    required this.title,
    required this.url,
    this.durationSeconds,
    required this.index,
  });

  factory AudioChapter.fromJson(Map<String, dynamic> json) {
    return AudioChapter(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      durationSeconds: json['duration_seconds'] as int?,
      index: json['index'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'duration_seconds': durationSeconds,
      'index': index,
    };
  }

  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
