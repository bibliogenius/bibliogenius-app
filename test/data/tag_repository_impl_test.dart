import 'package:bibliogenius/data/repositories_impl/tag_repository_impl.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_classes.dart';

class _StubApiService extends MockApiService {
  List<Tag> tags = [];

  @override
  Future<List<Tag>> getTags() async => tags;
}

void main() {
  // The core sorts by raw bytes ("Zola" before "écrits"); every flat shelf
  // list in the app reads through here, so the reader's order is set once.
  test('getTags lists shelves in compareShelfNames order', () async {
    final api = _StubApiService()
      ..tags = [
        Tag(id: '1', name: 'Bureau', count: 0),
        Tag(id: '2', name: 'Zola', count: 0),
        Tag(id: '3', name: 'atelier', count: 0),
        Tag(id: '4', name: 'écrits', count: 0),
      ];

    final tags = await TagRepositoryImpl(api).getTags();

    expect(tags.map((t) => t.name), ['atelier', 'Bureau', 'écrits', 'Zola']);
  });
}
