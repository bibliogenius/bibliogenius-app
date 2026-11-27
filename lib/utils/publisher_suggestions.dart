import 'search_text.dart';

/// The publishers of the library, one per name, for the publisher field's
/// suggestions. Spellings that differ only by case, accents or spacing count
/// as one name, written as most books write it (the first one met on a tie),
/// so the suggestion keeps the spelling the user already uses. Sorted
/// alphabetically, accents and case ignored.
List<String> distinctPublishers(Iterable<String?> publishers) {
  // Folded name -> its spellings, in the order met, with their counts.
  final spellings = <String, Map<String, int>>{};
  for (final raw in publishers) {
    final name = raw?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (name.isEmpty) continue;
    final counts = spellings.putIfAbsent(foldForSearch(name), () => {});
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final names = spellings.keys.toList()..sort();
  return [for (final name in names) _mostUsed(spellings[name]!)];
}

String _mostUsed(Map<String, int> counts) => counts.entries
    .reduce((best, next) => next.value > best.value ? next : best)
    .key;

/// The names of [publishers] to suggest for the text [typed] in the field:
/// those that start with it first, then those that contain it, accents and
/// case ignored. The name exactly as typed is left out, there is nothing to
/// complete; a name that differs from it only by case or accents stays, to
/// offer the library's spelling.
List<String> publisherSuggestions(List<String> publishers, String typed) {
  final text = typed.trim();
  final query = foldForSearch(text);
  if (query.isEmpty) return const [];
  final starting = <String>[];
  final containing = <String>[];
  for (final name in publishers) {
    if (name == text) continue;
    final folded = foldForSearch(name);
    if (folded.startsWith(query)) {
      starting.add(name);
    } else if (folded.contains(query)) {
      containing.add(name);
    }
  }
  return [...starting, ...containing];
}
