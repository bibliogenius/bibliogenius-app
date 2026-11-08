/// Which shelf a name stored in a book's subjects stands for: the same rule
/// as the core's `ShelfSpelling`, so a shelf page shows the books its count
/// takes in.
///
/// A name some shelf carries exactly is that shelf's; otherwise the first
/// shelf, in name order, that differs from it by case alone; otherwise it
/// stands for itself. Accents stay apart.
class ShelfSpelling {
  final Set<String> _exact;
  final Map<String, String> _byCase;

  ShelfSpelling._(this._exact, this._byCase);

  /// From the names the shelves carry, in any order.
  factory ShelfSpelling(Iterable<String> names) {
    final sorted = names.toList()..sort();
    final byCase = <String, String>{};
    for (final name in sorted) {
      byCase.putIfAbsent(name.trim().toLowerCase(), () => name);
    }
    return ShelfSpelling._(sorted.toSet(), byCase);
  }

  /// The shelf [name] stands for, spelled as the shelf is.
  String shelfOf(String name) {
    final trimmed = name.trim();
    if (_exact.contains(trimmed)) return trimmed;
    return _byCase[trimmed.toLowerCase()] ?? trimmed;
  }
}
