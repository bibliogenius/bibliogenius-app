import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/avatar_config.dart';
import 'package:bibliogenius/widgets/library_avatar.dart';

Widget _harness(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

LibraryAvatar _avatar({required AvatarConfig? config, String name = 'Chloe'}) =>
    LibraryAvatar(
      config: config,
      name: name,
      radius: 22,
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
    );

void main() {
  group('LibraryAvatar', () {
    testWidgets('renders the configured avatar instead of the letter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _avatar(
            config: const AvatarConfig(seed: 'chloe', style: 'avataaars'),
          ),
        ),
      );

      expect(
        find.byType(CachedNetworkImage),
        findsOneWidget,
        reason:
            'A peer that configured an avatar must show it on its library '
            'card, not the first letter of its name.',
      );
    });

    testWidgets('falls back to local initials when no avatar is configured', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_avatar(config: null)));

      expect(find.text('C'), findsOneWidget);
      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason:
            'Without a configured avatar the disc must stay local: no network '
            'request, and no library name handed to a third party, just to '
            'draw two letters.',
      );
    });

    testWidgets('shows the initials while the remote avatar is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _avatar(
            config: const AvatarConfig(seed: 'chloe', style: 'avataaars'),
          ),
        ),
      );

      expect(
        find.text('C'),
        findsOneWidget,
        reason:
            'The placeholder keeps the identity readable offline, where the '
            'DiceBear image never resolves.',
      );
    });

    testWidgets('falls back to "?" for an empty name', (tester) async {
      await tester.pumpWidget(_harness(_avatar(config: null, name: '')));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('a generated library name shows both ends, not just "B"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_avatar(config: null, name: 'Bibliothèque de iPad de Chloé')),
      );

      expect(
        find.text('BC'),
        findsOneWidget,
        reason:
            'Generated names all open with "Bibliothèque de", so the first '
            'letter alone renders "B" for every library in the list.',
      );
    });

    testWidgets('keeps the initials out of the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness(_avatar(config: null)));

      expect(find.text('C'), findsOneWidget);
      expect(
        find.bySemanticsLabel('C'),
        findsNothing,
        reason:
            'Every call site shows the library name next to the disc, so '
            'announcing the initials first would just make the reader spell '
            'the name twice.',
      );
      handle.dispose();
    });

    testWidgets('renders the genie mascot from the local asset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _avatar(
            config: const AvatarConfig(seed: 'genie', style: 'genie'),
          ),
        ),
      );

      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason: 'The genie avatar is bundled, it must not hit DiceBear.',
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('LibraryAvatar.initialsFor', () {
    test('takes the first and last word, matching the previous renderer', () {
      expect(LibraryAvatar.initialsFor('Bibliothèque de iPad de Chloé'), 'BC');
      expect(LibraryAvatar.initialsFor('Library of MacBook-Pro'), 'LM');
    });

    test('drops the generated name tag instead of turning it into a letter', () {
      expect(
        LibraryAvatar.initialsFor('Bibliothèque de iMac #A3F'),
        'BI',
        reason:
            'compute_default_library_name_seed appends "#<tag>", which is not '
            'an initial.',
      );
    });

    test('a single word yields a single letter', () {
      expect(LibraryAvatar.initialsFor('Chloé'), 'C');
    });

    test('keeps a letter outside the BMP whole', () {
      // U+10348 GOTHIC LETTER HWAIR is a surrogate pair: indexing the string
      // with [0] returns half of it, which renders as a replacement glyph.
      expect(
        LibraryAvatar.initialsFor('\u{10348}ibliothek von Chloé'),
        '\u{10348}C',
      );
    });

    test('falls back to "?" when nothing usable remains', () {
      expect(LibraryAvatar.initialsFor(''), '?');
      expect(LibraryAvatar.initialsFor('   '), '?');
      expect(LibraryAvatar.initialsFor('#123 @!'), '?');
    });
  });

  group('AvatarConfig.tryParse', () {
    test('parses a stored avatar_config JSON string', () {
      final json = jsonEncode(
        const AvatarConfig(seed: 'chloe', style: 'lorelei').toJson(),
      );

      final parsed = AvatarConfig.tryParse(json);

      expect(parsed, isNotNull);
      expect(parsed!.style, 'lorelei');
      expect(parsed.seed, 'chloe');
    });

    test('returns null for null, empty and malformed input', () {
      expect(AvatarConfig.tryParse(null), isNull);
      expect(AvatarConfig.tryParse(''), isNull);
      expect(AvatarConfig.tryParse('not json'), isNull);
      expect(
        AvatarConfig.tryParse('["array"]'),
        isNull,
        reason: 'A valid JSON value of the wrong shape must not throw.',
      );
    });
  });
}
