class Tag {
  final String name;
  final int count;

  Tag({required this.name, required this.count});

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      name: json['name'] as String,
      count: json['count'] as int,
    );
  }
}
