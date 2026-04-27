// Unit tests for content_languages parsing and locale partitioning.
// These tests must pass BEFORE the model/helper changes are wired into the UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:bibliogenius/services/curated_lists_service.dart';

YamlMap _yaml(String content) => loadYaml(content) as YamlMap;

const _yamlWithContentLanguages = '''
id: sample-en
version: 1
title:
  en: Sample
description:
  en: Sample description
tags: [sample]
content_languages: [en, fr]
books:
  - isbn: "9780000000001"
    note: "Book one"
''';

const _yamlWithoutContentLanguages = '''
id: sample-legacy
version: 1
title:
  en: Legacy
description:
  en: Legacy description
tags: [legacy]
books:
  - isbn: "9780000000002"
''';

const _yamlWithSingleLanguage = '''
id: sample-single
version: 1
title:
  fr: Échantillon
description:
  fr: Description
tags: [sample]
content_languages: [fr]
books:
  - isbn: "9780000000003"
''';

void main() {
  group('CuratedList.fromYaml - content_languages parsing', () {
    test('parses content_languages list when present', () {
      final list = CuratedList.fromYaml(_yaml(_yamlWithContentLanguages));
      expect(list.contentLanguages, equals(['en', 'fr']));
    });

    test('defaults to empty list when field is absent', () {
      final list = CuratedList.fromYaml(_yaml(_yamlWithoutContentLanguages));
      expect(list.contentLanguages, isEmpty);
    });

    test('parses single-element list', () {
      final list = CuratedList.fromYaml(_yaml(_yamlWithSingleLanguage));
      expect(list.contentLanguages, equals(['fr']));
    });
  });

  group('partitionCuratedListsByLanguage', () {
    CuratedList buildList(String id, List<String> contentLangs) {
      return CuratedList(
        id: id,
        version: 1,
        title: {'en': id},
        description: {'en': id},
        tags: const [],
        books: const [],
        contentLanguages: contentLangs,
      );
    }

    test('places lists with matching language in inYourLanguages', () {
      final lists = [
        buildList('fr-list', ['fr']),
        buildList('en-list', ['en']),
      ];
      final result = partitionCuratedListsByLanguage(lists, {'fr'});
      expect(result.inYourLanguages.map((l) => l.id), equals(['fr-list']));
      expect(result.otherLanguages.map((l) => l.id), equals(['en-list']));
    });

    test('any-language overlap is enough to match', () {
      final lists = [
        buildList('multi', ['en', 'fr']),
      ];
      final result = partitionCuratedListsByLanguage(lists, {'fr'});
      expect(result.inYourLanguages.map((l) => l.id), equals(['multi']));
      expect(result.otherLanguages, isEmpty);
    });

    test('lists without content_languages fall to otherLanguages', () {
      final lists = [buildList('unknown', const [])];
      final result = partitionCuratedListsByLanguage(lists, {'fr', 'en'});
      expect(result.inYourLanguages, isEmpty);
      expect(result.otherLanguages.map((l) => l.id), equals(['unknown']));
    });

    test('preserves order within each partition', () {
      final lists = [
        buildList('a-fr', ['fr']),
        buildList('b-en', ['en']),
        buildList('c-fr', ['fr']),
        buildList('d-de', ['de']),
      ];
      final result = partitionCuratedListsByLanguage(lists, {'fr'});
      expect(result.inYourLanguages.map((l) => l.id), equals(['a-fr', 'c-fr']));
      expect(result.otherLanguages.map((l) => l.id), equals(['b-en', 'd-de']));
    });

    test('empty user languages pushes everything to otherLanguages', () {
      final lists = [
        buildList('fr-list', ['fr']),
        buildList('en-list', ['en']),
      ];
      final result = partitionCuratedListsByLanguage(lists, const <String>{});
      expect(result.inYourLanguages, isEmpty);
      expect(result.otherLanguages.length, equals(2));
    });
  });
}
