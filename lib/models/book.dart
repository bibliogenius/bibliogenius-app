class Book {
  final int? id;
  final String title;
  final String? isbn;
  final String? summary;
  final String? publisher;
  final int? publicationYear;

  Book({
    this.id,
    required this.title,
    this.isbn,
    this.summary,
    this.publisher,
    this.publicationYear,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'],
      title: json['title'],
      isbn: json['isbn'],
      summary: json['summary'],
      publisher: json['publisher'],
      publicationYear: json['publication_year'],
    );
  }

  Map<String, dynamic> toJson() {
    final now = DateTime.now().toIso8601String();
    return {
      'title': title,
      'isbn': isbn,
      'summary': summary,
      'publisher': publisher,
      'publication_year': publicationYear,
      'created_at': now,
      'updated_at': now,
    };
  }
}
