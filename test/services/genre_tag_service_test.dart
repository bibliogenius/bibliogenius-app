import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/services/genre_tag_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every write so the tests can assert on what was created, and on what
/// was NOT created.
class _RecordingTagRepository implements TagRepository {
  final List<Tag> tags;
  final List<String> created = [];
  int _nextId = 100;

  _RecordingTagRepository([List<Tag>? initial]) : tags = [...?initial];

  @override
  Future<List<Tag>> getTags() async => List.of(tags);

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    created.add(name);
    final tag = Tag(
      id: 'uuid-${_nextId++}',
      name: name,
      parentId: parentId,
      count: 0,
    );
    tags.add(tag);
    return tag;
  }

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteTag(String uuid) async => throw UnimplementedError();
}

Tag _shelf(String id, String name, {String? parentId}) =>
    Tag(id: id, name: name, parentId: parentId, count: 0);

void main() {
  group('GenreTagService.resolveShelfChain', () {
    test('creates nothing for a library where no genre is ever picked', () async {
      final repo = _RecordingTagRepository();
      GenreTagService(repo);

      expect(repo.created, isEmpty);
      expect(repo.tags, isEmpty);
    });

    test('lazily creates the Genre parent then the genre itself', () async {
      final repo = _RecordingTagRepository();
      final service = GenreTagService(repo);

      final leaf = await service.resolveShelfChain(['Genre', 'Polar']);

      expect(repo.created, ['Genre', 'Polar']);
      expect(leaf.name, 'Polar');

      final root = repo.tags.firstWhere((t) => t.name == 'Genre');
      expect(root.parentId, isNull);
      expect(leaf.parentId, root.id);
    });

    test('reuses the existing chain for the second book of the same genre', () async {
      final repo = _RecordingTagRepository();
      final service = GenreTagService(repo);

      final first = await service.resolveShelfChain(['Genre', 'Polar']);
      repo.created.clear();

      final second = await service.resolveShelfChain(['Genre', 'Polar']);

      expect(repo.created, isEmpty, reason: 'the shelf already exists');
      expect(second.id, first.id);
    });

    test('creates only the missing level when the Genre parent already exists', () async {
      final repo = _RecordingTagRepository([_shelf('uuid-1', 'Genre')]);
      final service = GenreTagService(repo);

      final leaf = await service.resolveShelfChain(['Genre', 'Science-fiction']);

      expect(repo.created, ['Science-fiction']);
      expect(leaf.parentId, 'uuid-1');
    });

    test('reuses a shelf the user already curates instead of violating UNIQUE(name)', () async {
      // `tags.name` is unique across the whole tree: creating a second "Polar"
      // under "Genre" would fail the constraint. The user's own shelf wins, and
      // is left exactly where it is.
      final repo = _RecordingTagRepository([_shelf('uuid-9', 'Polar')]);
      final service = GenreTagService(repo);

      final leaf = await service.resolveShelfChain(['Genre', 'Polar']);

      expect(repo.created, isEmpty, reason: 'no Genre parent is forced on a reused shelf');
      expect(leaf.id, 'uuid-9');
      expect(leaf.parentId, isNull, reason: 'the existing shelf must not be re-parented');
    });

    test('files a subgenre under its genre, creating the whole chain once', () async {
      final repo = _RecordingTagRepository();
      final service = GenreTagService(repo);

      final leaf = await service.resolveShelfChain(['Genre', 'Polar', 'Thriller']);

      expect(repo.created, ['Genre', 'Polar', 'Thriller']);

      final polar = repo.tags.firstWhere((t) => t.name == 'Polar');
      expect(leaf.name, 'Thriller');
      expect(leaf.parentId, polar.id);
    });

    test('adopts a synthetic subject-derived shelf, which has no tags row yet', () async {
      // `get_all_tags` synthesises entries from `books.subjects` with an empty
      // id. Nothing backs them in `tags`, so inserting is safe and files the
      // existing books under Genre rather than leaving a duplicate root.
      final repo = _RecordingTagRepository([_shelf('', 'Manga')]);
      final service = GenreTagService(repo);

      final leaf = await service.resolveShelfChain(['Genre', 'Manga']);

      expect(repo.created, ['Genre', 'Manga']);
      expect(leaf.isPersisted, isTrue);
    });

    test('matches an existing shelf case-insensitively', () async {
      final repo = _RecordingTagRepository([_shelf('uuid-1', 'genre')]);
      final service = GenreTagService(repo);

      await service.resolveShelfChain(['Genre', 'Romance']);

      expect(repo.created, ['Romance'], reason: 'no second "Genre" shelf');
    });
  });
}
