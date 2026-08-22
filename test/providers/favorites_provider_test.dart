import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/models/collection_deletion_preview.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/favorites_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory repository double: only the favorites surface is scripted, the
/// rest throws if reached.
class _FakeCollectionRepository implements CollectionRepository {
  Set<String> favorites = {};
  Collection? candidate;
  int listCalls = 0;
  final List<String> adopted = [];

  @override
  Future<bool> toggleFavoriteBook(String bookId) async {
    if (favorites.contains(bookId)) {
      favorites.remove(bookId);
      return false;
    }
    favorites.add(bookId);
    return true;
  }

  @override
  Future<List<String>> getFavoriteBookIds() async {
    listCalls++;
    return favorites.toList();
  }

  @override
  Future<Collection?> getFavoritesAdoptionCandidate() async => candidate;

  @override
  Future<void> adoptFavoritesCollection(String collectionId) async {
    adopted.add(collectionId);
    candidate = null;
  }

  @override
  Future<bool> seedFavoritesCollection() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Collection _manualFavoris() => Collection(
  id: 'mine',
  name: 'Favoris',
  source: 'manual',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  totalBooks: 2,
);

void main() {
  late _FakeCollectionRepository repo;
  late BookRefreshNotifier notifier;
  late FavoritesProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _FakeCollectionRepository();
    notifier = BookRefreshNotifier();
    provider = FavoritesProvider(repo, notifier);
  });

  tearDown(() => provider.dispose());

  test('toggle flips membership and updates the cached set instantly', () async {
    expect(provider.isFavorite('b1'), isFalse);

    expect(await provider.toggle('b1'), isTrue);
    expect(provider.isFavorite('b1'), isTrue);

    expect(await provider.toggle('b1'), isFalse);
    expect(provider.isFavorite('b1'), isFalse);
  });

  test('ensureLoaded caches; a catalogue mutation invalidates and reloads', () async {
    repo.favorites = {'a'};
    await provider.ensureLoaded();
    expect(provider.isFavorite('a'), isTrue);
    final callsAfterLoad = repo.listCalls;

    // No mutation: a second ensureLoaded is served from the cache.
    await provider.ensureLoaded();
    expect(repo.listCalls, callsAfterLoad);

    // A catalogue mutation (BookRefreshNotifier ping) reloads eagerly.
    repo.favorites = {'a', 'b'};
    notifier.refresh();
    await Future<void>.delayed(Duration.zero);
    await provider.ensureLoaded();
    expect(provider.isFavorite('b'), isTrue);
  });

  test('adoption is proposed while a candidate exists and none declined', () async {
    repo.candidate = _manualFavoris();
    final candidate = await provider.adoptionCandidate();
    expect(candidate?.id, 'mine');
  });

  test('a declined adoption is remembered and never proposed again', () async {
    repo.candidate = _manualFavoris();
    await provider.declineAdoption();

    // Even though the repository still has a candidate, the device-local
    // refusal wins: the question is never asked again.
    expect(await provider.adoptionCandidate(), isNull);

    // The refusal survives a new provider instance (persisted preference).
    final second = FavoritesProvider(repo, notifier);
    expect(await second.adoptionCandidate(), isNull);
    second.dispose();
  });

  test('adopt flips the collection and refreshes the member set', () async {
    repo.candidate = _manualFavoris();
    repo.favorites = {'m1', 'm2'};

    await provider.adopt(repo.candidate!);

    expect(repo.adopted, ['mine']);
    expect(provider.isFavorite('m1'), isTrue);
    expect(provider.isFavorite('m2'), isTrue);
  });
}
