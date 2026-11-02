import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';

/// [shelf] itself when it has a `tags` row, otherwise the row created for
/// it. Null stays null: the first level needs no row.
///
/// A name known only from the books' subjects (see [Tag.isPersisted]) cannot
/// parent another shelf: its `legacy:` id names no row, so a shelf filed
/// under it would point nowhere and show back at the first level. The core
/// lists such a name at the first level, so that is where its row goes.
Future<Tag?> shelfWithRow(TagRepository tags, Tag? shelf) async {
  if (shelf == null || shelf.isPersisted) return shelf;
  return tags.createTag(shelf.name);
}
