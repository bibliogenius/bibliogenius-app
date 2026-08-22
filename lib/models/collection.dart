class Collection {
  final String id;
  final String name;
  final String? description;
  final String source;
  final String createdAt;
  final String updatedAt;
  final int totalBooks;
  final int ownedBooks;

  Collection({
    required this.id,
    required this.name,
    this.description,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.totalBooks = 0,
    this.ownedBooks = 0,
  });

  /// A series-typed collection: its members form an ordered reading list and
  /// drive the frise on the book-detail screen.
  bool get isSeries => source == 'series';

  /// THE favorites collection (ADR-064): membership is the favorite flag.
  /// Its stored name may be the technical sentinel; display sites must
  /// render the translated label instead (see CollectionDisplay).
  bool get isFavorites => source == 'favorites';

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      source: json['source'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      totalBooks: json['total_books'] ?? 0,
      ownedBooks: json['owned_books'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'source': source,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'total_books': totalBooks,
      'owned_books': ownedBooks,
    };
  }
}
