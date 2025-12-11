class Quote {
  final String text;
  final String author;
  final String source;
  final String? coverUrl;

  Quote({
    required this.text,
    required this.author,
    required this.source,
    this.coverUrl,
  });
}
