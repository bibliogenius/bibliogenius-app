class Quote {
  final String text;
  final String author;
  final String source;
  final String? coverUrl;
  final String? locale;
  final DateTime? cachedAt;

  Quote({
    required this.text,
    required this.author,
    required this.source,
    this.coverUrl,
    this.locale,
    this.cachedAt,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      text: json['text'] ?? '',
      author: json['author'] ?? 'Unknown',
      source: json['source'] ?? '',
      coverUrl: json['coverUrl'],
      locale: json['locale'],
      cachedAt: json['cachedAt'] != null 
          ? DateTime.tryParse(json['cachedAt']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'author': author,
      'source': source,
      'coverUrl': coverUrl,
      'locale': locale,
      'cachedAt': cachedAt?.toIso8601String(),
    };
  }

  bool get isExpired {
    if (cachedAt == null) return true;
    return DateTime.now().difference(cachedAt!).inHours >= 24;
  }
}
