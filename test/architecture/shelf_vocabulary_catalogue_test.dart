// Guard: the words the app uses for shelves and collections.
//
// One object carried six names (shelf, category, tags, labels, subject,
// "rayons") and the top of the tree three labels, while no text said when to
// take a shelf rather than a collection. The shelves help even cited "To read"
// and "Favorites" as shelf examples: a reading status and an automatic
// collection. This test pins the fix in every shipped catalogue, so a later
// rewording in one language cannot drift away from the others.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _languages = [
  'en',
  'fr',
  'es',
  'de',
  'pt-BR',
  'it',
  'tr',
  'bg',
  'ja',
  'ko',
  'zh',
];

/// msgid -> unescaped msgstr, for a `.po` file without plural entries.
Map<String, String> _entries(String path) {
  final lines = File(path).readAsLinesSync();
  final result = <String, String>{};
  String? id;
  StringBuffer? value;
  void flush() {
    if (id != null && value != null) result[id!] = value.toString();
    id = null;
    value = null;
  }

  String unquote(String quoted) => quoted
      .substring(1, quoted.length - 1)
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\');

  for (final line in lines) {
    if (line.startsWith('msgid "')) {
      flush();
      id = unquote(line.substring(6));
    } else if (line.startsWith('msgstr "')) {
      value = StringBuffer(unquote(line.substring(7)));
    } else if (line.startsWith('"') && value != null) {
      value!.write(unquote(line));
    } else if (line.trim().isEmpty) {
      flush();
    }
  }
  flush();
  return result..remove('');
}

/// The shelf word inside "sub-shelf", where a test can name it: the one of
/// the shelves tab, in the singular.
const _subShelfWord = {
  'fr': 'étagère',
  'es': 'estantería',
  'pt-BR': 'prateleira',
  'ja': '本棚',
  'ko': '책장',
  'zh': '书架',
};

String _po(String lang) => 'assets/i18n/$lang.po';

void main() {
  final catalogues = {for (final l in _languages) l: _entries(_po(l))};
  final template = _entries('assets/i18n/messages.pot');

  const added = [
    'shelf_concept',
    'collection_concept',
    'shelf_or_collection_rule',
    'first_level',
    // The shelf picker of the book form.
    'choose_shelves',
    'choose_shelves_subtitle',
    'search_or_create_shelf_hint',
    'create_shelf_named',
    'create_shelf_first_level_hint',
    'create_shelf_inside',
    'create_shelf_in_title',
    'create_shelf_in_subtitle',
    'create_shelf_first_level_instead',
    'filter_shelves_hint',
    'shelf_already_exists',
    'shelf_already_exists_in',
    'shelf_in_path',
    'shelf_name_taken_hint',
    'recent_shelves',
    'all_shelves',
    'matching_shelves',
    'add_shelf_named',
    // Moving a shelf through the placement tree.
    'move_shelf_to',
    'move_shelf_to_title',
    'move_shelf_to_subtitle',
    'move_shelf_to_first_level',
    'shelf_current_place',
    'shelf_moved_under',
    'shelf_moved_to_first_level',
    // The shelves tab tree: its row controls and the drag.
    'shelf_expand_named',
    'shelf_collapse_named',
    'move_shelf_named',
    'shelf_actions_named',
    'shelf_drop_into',
    'shelf_being_moved',
    // Undo in the shelves tab: a deletion waits on it, a rename's Undo can
    // find its old name taken.
    'shelf_deleted_named',
    'shelf_undo_name_taken',
  ];

  // Replaced by the keys above, or never read by the app.
  const retired = [
    'none',
    'root_tag',
    'root_level',
    'no_shelves_hint',
    'collections_helper',
    'add_tags',
    'import_options',
    'select_tags',
    'hierarchical_tag_hint',
    // Saving a shelf order now says what it changes: see
    // shelf_order_saved_sort_hint.
    'shelf_order_saved',
    // The old shelf picker: its title, search hint and create form, replaced
    // by choose_shelves, search_or_create_shelf_hint and create_shelf_named.
    'manage_tags',
    'search_shelves_hint',
    'create_new_tag',
    'tag_name_hint',
    // The old shelf tree's empty search; the picker lists matches instead.
    'no_shelves_match',
    // The radio-button move dialog, replaced by the placement tree.
    'moving',
    'select_new_parent',
    'move',
    // The shelves grid: its count badge and the parent card's way to its
    // books. The tree lists every shelf, and a row's tap opens its books.
    'view_shelf_books',
    'displayed_shelves_count',
    'displayed_shelves_count_plural',
  ];

  test('the new keys exist, translated, in every catalogue and the template', () {
    for (final key in added) {
      expect(template.containsKey(key), isTrue, reason: '$key not in .pot');
      for (final lang in _languages) {
        expect(
          catalogues[lang]![key],
          isNot(anyOf(isNull, isEmpty)),
          reason: '$key missing or empty in $lang.po',
        );
      }
    }
  });

  test('the retired keys are gone from the catalogues, the template and lib/',
      () {
    for (final key in retired) {
      expect(template.containsKey(key), isFalse, reason: '$key still in .pot');
      for (final lang in _languages) {
        expect(
          catalogues[lang]!.containsKey(key),
          isFalse,
          reason: '$key still in $lang.po',
        );
      }
    }
    final pattern = RegExp(
      "translate\\(\\s*\\w+\\s*,\\s*'(${retired.join('|')})'",
    );
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => pattern.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'retired keys still translated');
  });

  test('the move messages keep their placeholders in every language', () {
    const placeholders = {
      'move_shelf_to_title': ['{name}'],
      'shelf_moved_under': ['{name}', '{parent}'],
      'shelf_moved_to_first_level': ['{name}'],
      'shelf_expand_named': ['{name}'],
      'shelf_collapse_named': ['{name}'],
      'move_shelf_named': ['{name}'],
      'shelf_actions_named': ['{name}'],
      'shelf_drop_into': ['{name}'],
      'shelf_deleted_named': ['%s'],
      'shelf_undo_name_taken': ['%s'],
    };
    for (final lang in _languages) {
      placeholders.forEach((key, holes) {
        for (final hole in holes) {
          expect(
            catalogues[lang]![key],
            contains(hole),
            reason: '$lang.po: $key lost $hole',
          );
        }
      });
    }
  });

  test('every catalogue holds the same keys as the template', () {
    final expected = template.keys.toSet();
    for (final lang in _languages) {
      final ids = catalogues[lang]!.keys.toSet();
      expect(ids.difference(expected), isEmpty, reason: 'extra in $lang.po');
      expect(expected.difference(ids), isEmpty, reason: 'missing in $lang.po');
    }
  });

  test('the help and field hints carry the same sentences in every language',
      () {
    for (final lang in _languages) {
      final c = catalogues[lang]!;
      final shelf = c['shelf_concept']!;
      final collection = c['collection_concept']!;
      final rule = c['shelf_or_collection_rule']!;

      void quotes(String key, String sentence) => expect(
        c[key],
        contains(sentence),
        reason: '$lang.po: $key must quote the shared sentence',
      );

      quotes('help_ctx_shelves_content', shelf);
      quotes('help_ctx_shelves_content', rule);
      quotes('help_desc_organize_shelf', shelf);
      quotes('help_desc_organize_shelf', rule);
      quotes('help_ctx_collections_content', collection);
      quotes('help_ctx_collections_content', rule);
      quotes('help_desc_collections', collection);
      quotes('help_desc_collections', rule);

      // The field hint is the first sentence of the shelf concept, without
      // its "Shelf:" lead, which the field label already says.
      expect(
        shelf.toLowerCase(),
        contains(c['tags_helper']!.toLowerCase()),
        reason: '$lang.po: tags_helper must come from shelf_concept',
      );

      // One word for the object: the form label is the tab name.
      expect(
        c['tags_label'],
        c['shelves'],
        reason: '$lang.po: the form calls shelves what the tab calls them',
      );
    }
  });

  test('the shelves help no longer cites a reading status or a collection',
      () {
    const examples = {
      'en': ['To Read', 'Favorites'],
      'fr': ['À lire', 'Favoris'],
      'de': ['Favoriten'],
    };
    examples.forEach((lang, words) {
      for (final key in ['help_ctx_shelves_content', 'help_desc_organize_shelf']) {
        for (final word in words) {
          expect(
            catalogues[lang]![key],
            isNot(contains(word)),
            reason: '$lang.po: $key still cites "$word"',
          );
        }
      }
    });
  });

  test('French says "étagère", never "catégorie", for a shelf', () {
    // Keys that mean something else by "catégorie": curated list groups,
    // statistics groups, notification kinds.
    const otherMeaning = {
      'curated_no_lists',
      'no_lists_in_category',
      'rating_by_group',
      'notif_enabled_help',
    };
    final offenders = catalogues['fr']!.entries
        .where((e) => RegExp('catégor', caseSensitive: false).hasMatch(e.value))
        .map((e) => e.key)
        .where((k) => !otherMeaning.contains(k))
        .toList();
    expect(offenders, isEmpty);
    expect(catalogues['fr']!['help_desc_recommendations'], isNot(contains('rayons')));
  });

  test('a label that names the shelves uses the word of the shelves tab', () {
    // Japanese once said 棚 here while the tab says 本棚: one object, one
    // word, in every language.
    const keys = ['all_shelves'];
    for (final lang in _languages) {
      // A sub-shelf is a shelf: the singular of the tab's word, wherever a
      // language spells it as a part of the compound.
      final sub = catalogues[lang]!['add_sub_shelf']!;
      if (_subShelfWord.containsKey(lang)) {
        expect(sub, contains(_subShelfWord[lang]!), reason: '$lang.po');
      }
      final word = catalogues[lang]!['shelves']!.toLowerCase();
      for (final key in keys) {
        expect(
          catalogues[lang]![key]!.toLowerCase(),
          contains(word),
          reason: '$lang.po: $key must say "$word"',
        );
      }
    }
  });

  test('the Undo messages call a shelf what the shelves tab calls it', () {
    const keys = ['shelf_deleted_named', 'shelf_undo_name_taken'];
    _subShelfWord.forEach((lang, word) {
      for (final key in keys) {
        expect(
          catalogues[lang]![key]!.toLowerCase(),
          contains(word),
          reason: '$lang.po: $key must say "$word"',
        );
      }
    });
  });

  test('Spanish and Portuguese keep one word on the shelves empty state', () {
    // Both catalogues also hold "estante", the word the app does not use for
    // a shelf: the empty-state title once said it right above the sentence
    // that says "estantería" / "prateleira".
    const keys = [
      'no_shelves_title',
      'create_first_shelf',
      'shelf_concept',
      'shelf_or_collection_rule',
      'shelves',
      'tags_label',
      'help_ctx_shelves_content',
      'help_desc_organize_shelf',
      // The shelf order: its sort entry and the message that announces it.
      'sort_shelf_order',
      'shelf_order_saved_sort_hint',
      // The shelf picker of the book form.
      'choose_shelves',
      'search_or_create_shelf_hint',
      'create_shelf_inside',
      'create_shelf_in_subtitle',
      'filter_shelves_hint',
      'shelf_name_taken_hint',
      'all_shelves',
      'matching_shelves',
      'add_shelf_named',
      // Moving a shelf.
      'move_shelf_to_subtitle',
      // The shelves tab tree.
      'add_sub_shelf',
    ];
    for (final lang in ['es', 'pt-BR']) {
      for (final key in keys) {
        expect(
          catalogues[lang]![key],
          isNot(matches(RegExp(r'\bestantes?\b', caseSensitive: false))),
          reason: '$lang.po: $key',
        );
      }
    }
  });

  test('English says "shelves", never "tags", outside the CSV export', () {
    for (final key in ['enable_taxonomy', 'sub_categories', 'move_shelf_hint']) {
      expect(
        catalogues['en']![key],
        isNot(matches(RegExp(r'\b(tags?|categor)', caseSensitive: false))),
        reason: 'en.po: $key',
      );
    }
    // Unchanged on purpose: the CSV column header, for re-import.
    expect(catalogues['en']!['csv_header_tags'], 'tags');
    expect(catalogues['fr']!['csv_header_tags'], 'étiquettes');
  });
}
