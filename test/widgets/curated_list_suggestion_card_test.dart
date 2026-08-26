import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/curated_affinity_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:bibliogenius/widgets/compact_suggestion_card.dart';
import 'package:bibliogenius/widgets/curated_list_suggestion_card.dart';
import 'package:bibliogenius/widgets/suggestion_tile.dart';

/// ADR-066: the list card. A collection-format tile built from the reader's
/// OWN copies of the books in common, carrying its reason and its source,
/// and announcing all of it in ONE screen-reader label (ADR-061 A2).

CuratedAffinity _affinity({
  int owned = 3,
  int liked = 0,
  int total = 10,
  List<String> covers = const [],
}) {
  return CuratedAffinity(
    list: CuratedList(
      id: 'goncourt',
      version: 1,
      title: const {'en': 'Goncourt winners', 'fr': 'Lauréats Goncourt'},
      description: const {'en': '', 'fr': ''},
      tags: const [],
      books: const [],
      contentLanguages: const ['fr'],
    ),
    ownedCount: owned,
    likedCount: liked,
    totalCount: total,
    score: 0.3,
    ownedCoverUrls: covers,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'curated_affinity_reason': '{owned} books in common',
        'curated_affinity_reason_liked':
            '{owned} books in common, {liked} of them liked',
        'suggestion_badge_editorial': 'Selection',
        'recommendation_not_interested': 'Not interested',
      },
    });
  });

  Future<void> pump(
    WidgetTester tester,
    CuratedAffinity affinity, {
    VoidCallback? onTap,
    VoidCallback? onDismiss,
    CuratedCardLayout layout = CuratedCardLayout.strip,
    String? dismissTooltip,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: CuratedListSuggestionCard(
              affinity: affinity,
              onTap: onTap ?? () {},
              onDismiss: onDismiss,
              dismissTooltip: dismissTooltip,
              layout: layout,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the card names the list and its reason', (tester) async {
    await pump(tester, _affinity(owned: 3));

    expect(find.text('Goncourt winners'), findsOneWidget);
    expect(find.text('3 books in common'), findsOneWidget);
  });

  testWidgets('liked books are named only when there are some', (tester) async {
    // "3 books in common, 0 of them liked" would read as an accusation, and
    // zero liked is the common case: the signal is structurally sparse.
    await pump(tester, _affinity(owned: 3, liked: 2));
    expect(find.text('3 books in common, 2 of them liked'), findsOneWidget);

    await pump(tester, _affinity(owned: 3));
    expect(find.text('3 books in common'), findsOneWidget);
    expect(find.textContaining('liked'), findsNothing);
  });

  testWidgets('the artwork is built from the reader own covers', (
    tester,
  ) async {
    await pump(
      tester,
      _affinity(covers: const ['file:///a.jpg', 'file:///b.jpg']),
    );

    final covers = tester
        .widgetList<CachedBookCover>(find.byType(CachedBookCover))
        .map((w) => w.imageUrl)
        .toList();
    expect(covers, ['file:///a.jpg', 'file:///b.jpg']);
  });

  testWidgets('the strip artwork clamps to three covers, like the fan', (
    tester,
  ) async {
    // The payload still caps at four, from the era when this card drew a
    // 2x2 mosaic. A fourth layer only steepens the tilt.
    await pump(
      tester,
      _affinity(
        covers: const [
          'file:///a.jpg',
          'file:///b.jpg',
          'file:///c.jpg',
          'file:///d.jpg',
        ],
      ),
    );

    expect(find.byType(CachedBookCover), findsNWidgets(3));
  });

  testWidgets('the name gets more of the card than the artwork does', (
    tester,
  ) async {
    // The defect this pins: the artwork used to be a square as tall as the
    // strip, which left the name 48 points of the card's 168 and broke it
    // mid-word. The words are the only thing that identifies a LIST, so
    // they take the larger half.
    await pump(tester, _affinity(covers: const ['file:///a.jpg']));

    final title = tester.getRect(find.text('Goncourt winners'));
    final reason = tester.getRect(find.text('3 books in common'));
    final context = tester.element(find.byType(CuratedListSuggestionCard));
    final art = CuratedListSuggestionCard.stripArtWidth(context);

    expect(title.width, greaterThan(art));
    expect(reason.width, greaterThan(art));
  });

  testWidgets('no owned cover falls back to a placeholder, never to the '
      'list own remote art', (tester) async {
    await pump(tester, _affinity(covers: const []));

    expect(find.byType(CachedBookCover), findsNothing);
    expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
  });

  testWidgets('the card carries a source badge', (tester) async {
    await pump(tester, _affinity());
    expect(find.text('Selection'), findsOneWidget);
  });

  testWidgets('one composed announcement carries title, reason and source', (
    tester,
  ) async {
    await pump(tester, _affinity(owned: 4, liked: 1));

    final semantics = tester.getSemantics(
      find.byType(CuratedListSuggestionCard),
    );
    expect(
      semantics.label,
      'Goncourt winners, 4 books in common, 1 of them liked, Selection',
    );
    expect(
      semantics.hasFlag(SemanticsFlag.isButton),
      isTrue,
      reason: 'Rule A1: a tappable card announces itself as a button.',
    );
  });

  testWidgets('the card fits the strip height budget', (tester) async {
    // ADR-062 section 3: the strip must not grow. The card is exactly the
    // strip's height and an exact number of book-card widths.
    await pump(tester, _affinity());

    final size = tester.getSize(find.byType(CuratedListSuggestionCard));
    final context = tester.element(find.byType(CuratedListSuggestionCard));
    expect(size.height, CompactSuggestionCard.stripHeight(context));
    expect(size.width, CuratedListSuggestionCard.cardWidth(context));
  });

  group('the fan layout (the Collections screen)', () {
    testWidgets('the fan clamps to three covers', (tester) async {
      // The payload caps at four for the strip's 2x2. A fourth layer only
      // steepens the tilt, so the fan takes three and the widget clamps.
      await pump(
        tester,
        _affinity(
          covers: const [
            'file:///a.jpg',
            'file:///b.jpg',
            'file:///c.jpg',
            'file:///d.jpg',
          ],
        ),
        layout: CuratedCardLayout.fan,
      );

      final covers = tester
          .widgetList<CachedBookCover>(find.byType(CachedBookCover))
          .map((w) => w.imageUrl)
          .toList();
      expect(covers, ['file:///a.jpg', 'file:///b.jpg', 'file:///c.jpg']);
    });

    testWidgets('no owned cover falls back to the same placeholder', (
      tester,
    ) async {
      // Same rule as the mosaic: never the list's own remote art, which
      // would contradict the "these are your books" the artwork exists to
      // say, and would fetch from inside a scrolling strip.
      await pump(
        tester,
        _affinity(covers: const []),
        layout: CuratedCardLayout.fan,
      );

      expect(find.byType(CachedBookCover), findsNothing);
      expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
    });

    testWidgets('the name sits under the artwork, full card width', (
      tester,
    ) async {
      await pump(
        tester,
        _affinity(covers: const ['file:///a.jpg']),
        layout: CuratedCardLayout.fan,
      );

      final card = tester.getRect(find.byType(CuratedListSuggestionCard));
      final title = tester.getRect(find.text('Goncourt winners'));
      expect(title.top, greaterThan(card.top + card.height / 2));
      expect(title.width, greaterThan(card.width - 8));

      final context = tester.element(find.byType(CuratedListSuggestionCard));
      expect(card.width, CuratedListSuggestionCard.fanCardWidth(context));
    });

    testWidgets('the source is worded on the artwork, not left to a colour', (
      tester,
    ) async {
      await pump(tester, _affinity(), layout: CuratedCardLayout.fan);
      expect(find.text('SELECTION'), findsOneWidget);
    });

    testWidgets('both gestures stay reachable without a pointer', (
      tester,
    ) async {
      // The defect this pins: excludeSemantics drops the InkWell's actions,
      // and a long press is never synthesized back the way a tap is, so the
      // dismissal would be unreachable to a screen reader while every other
      // test on the card passed.
      var tapped = 0;
      var dismissed = 0;
      await pump(
        tester,
        _affinity(),
        onTap: () => tapped++,
        onDismiss: () => dismissed++,
        layout: CuratedCardLayout.fan,
      );

      final node = tester.getSemantics(find.byType(CuratedListSuggestionCard));
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(node.hintOverrides?.onLongPressHint, 'Not interested');

      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      owner.performAction(node.id, SemanticsAction.tap);
      owner.performAction(node.id, SemanticsAction.longPress);
      await tester.pump();

      expect(tapped, 1);
      expect(dismissed, 1);
    });
  });

  group('the row layout (the "Suggestions for you" page)', () {
    testWidgets('the text starts on the page tile grid', (tester) async {
      // The page is ONE column of tiles under one card, and its separators
      // are inset to a single left edge. A row starting its text anywhere
      // else makes the hairlines cut at two places down the same column.
      await pump(
        tester,
        _affinity(covers: const ['file:///a.jpg']),
        layout: CuratedCardLayout.row,
      );

      final card = tester.getRect(find.byType(CuratedListSuggestionCard));
      final title = tester.getRect(find.text('Goncourt winners'));
      expect(title.left - card.left, SuggestionTile.textOffset);
    });

    testWidgets('the dismissal is the page own close button, labelled', (
      tester,
    ) async {
      // Every other row on that page offers a close button, so a reader who
      // found it there looks for it here. A long press would be invisible.
      var dismissed = 0;
      await pump(
        tester,
        _affinity(),
        onDismiss: () => dismissed++,
        dismissTooltip: 'Not interested',
        layout: CuratedCardLayout.row,
      );

      await tester.tap(find.byTooltip('Not interested'));
      expect(dismissed, 1);
    });

    testWidgets('the close button survives the card excluded semantics', (
      tester,
    ) async {
      // The defect this pins: the card announces itself as one node with
      // `excludeSemantics`, and a close button swallowed by that subtree is
      // a button a screen reader cannot reach at all.
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _affinity(),
        onDismiss: () {},
        dismissTooltip: 'Not interested',
        layout: CuratedCardLayout.row,
      );

      final node = tester.getSemantics(find.byType(IconButton));
      expect(
        node.tooltip,
        'Not interested',
        reason: 'Rules A1/A4: the dismissal is a named button of its own.',
      );
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    testWidgets('the source is worded, in the page own badge', (tester) async {
      await pump(tester, _affinity(), layout: CuratedCardLayout.row);
      expect(find.byType(SuggestionSourceBadge), findsOneWidget);
      expect(find.text('Selection'), findsOneWidget);
    });
  });

  testWidgets('tapping opens the caller flow', (tester) async {
    var tapped = 0;
    await pump(tester, _affinity(), onTap: () => tapped++);

    await tester.tap(find.byType(CuratedListSuggestionCard));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('a long press dismisses when the surface offers it', (
    tester,
  ) async {
    var dismissed = 0;
    await pump(tester, _affinity(), onDismiss: () => dismissed++);

    await tester.longPress(find.byType(CuratedListSuggestionCard));
    await tester.pump();

    expect(dismissed, 1);
  });

  testWidgets('both gestures are reachable without a pointer', (tester) async {
    // `excludeSemantics: true` drops the InkWell own semantics, so the two
    // gestures exist for a finger and for nothing else unless the card
    // carries the actions itself. A tap has a synthesized fallback on some
    // platforms; a LONG PRESS has none anywhere, so the dismissal would be
    // unreachable to a screen reader while every test on this card passed.
    var tapped = 0;
    var dismissed = 0;
    await pump(
      tester,
      _affinity(),
      onTap: () => tapped++,
      onDismiss: () => dismissed++,
    );

    final node = tester.getSemantics(find.byType(CuratedListSuggestionCard));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);

    final owner = tester.binding.pipelineOwner.semanticsOwner!;
    owner.performAction(node.id, SemanticsAction.tap);
    owner.performAction(node.id, SemanticsAction.longPress);
    await tester.pump();

    expect(tapped, 1);
    expect(dismissed, 1);
  });

  testWidgets('the dismissal announces what the long press does', (
    tester,
  ) async {
    // A bare "double tap and hold" says nothing about what it costs. The
    // hint names the gesture, and it is the SAME wording the other
    // suggestion surfaces put on their dismiss button.
    await pump(tester, _affinity(), onDismiss: () {});

    final node = tester.getSemantics(find.byType(CuratedListSuggestionCard));
    expect(node.hintOverrides?.onLongPressHint, 'Not interested');
  });

  testWidgets('a surface offering no dismissal advertises none', (
    tester,
  ) async {
    await pump(tester, _affinity());

    final node = tester.getSemantics(find.byType(CuratedListSuggestionCard));
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isFalse,
    );
    expect(node.hintOverrides?.onLongPressHint, isNull);
  });
}
