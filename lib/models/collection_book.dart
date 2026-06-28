class CollectionBook {
  final String bookId;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? publisher;
  final int? publicationYear;
  final DateTime addedAt;
  final bool isOwned;

  CollectionBook({
    required this.bookId,
    required this.title,
    this.author,
    this.coverUrl,
    this.publisher,
    this.publicationYear,
    required this.addedAt,
    required this.isOwned,
  });

  factory CollectionBook.fromJson(Map<String, dynamic> json) {
    return CollectionBook(
      bookId: json['book_id'].toString(),
      title: json['title'],
      author: json['author'],
      coverUrl: json['cover_url'],
      publisher: json['publisher'],
      publicationYear: json['publication_year'],
      addedAt: DateTime.parse(json['added_at']),
      isOwned: json['is_owned'] ?? false,
    );
  }
}
